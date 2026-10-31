import Foundation

/// One subscription limit window, such as Claude's 5-hour session or weekly cap.
public struct QuotaWindow: Identifiable, Sendable, Equatable {
    /// Short label: the text in parentheses of OmniRoute's name ("session (5h)" → "5h").
    public let label: String
    /// Share of the window already used, 0…100.
    public let usedPercent: Double
    public let resetsAt: Date?
    /// How long the window lasts, when its name says so ("session (5h)" → 5 hours).
    public let duration: TimeInterval?

    public var id: String { label }

    public init(label: String, usedPercent: Double, resetsAt: Date?, duration: TimeInterval? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.duration = duration ?? Quotas.duration(of: label)
    }

    public enum Level: Sendable { case normal, high, critical }

    public var level: Level {
        usedPercent >= 95 ? .critical : usedPercent >= 80 ? .high : .normal
    }
}

/// Parses `GET /api/usage/<connectionId>`, which reports provider quotas as
/// `{"quotas": {"session (5h)": {"used", "total", "remainingPercentage", "resetAt", "unlimited"}}}`.
/// Any provider that reports quotas this way is supported, nothing is provider-specific.
public enum Quotas {
    public static func parse(_ data: Data) -> [QuotaWindow] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotas = object["quotas"] as? [String: Any] else { return [] }
        let windows = quotas.compactMap { name, value -> QuotaWindow? in
            guard let quota = value as? [String: Any], quota["unlimited"] as? Bool != true,
                  let used = usedPercent(quota) else { return nil }
            let reset = (quota["resetAt"] as? String).flatMap(parseDate)
            return QuotaWindow(label: label(for: name), usedPercent: min(max(used, 0), 100), resetsAt: reset,
                               duration: duration(of: name))
        }
        return sorted(windows)
    }

    /// The shortest window first, so the limit that runs out soonest sits on top:
    /// "5h" above "7d" above "30d". Windows of unknown length follow, soonest reset first.
    ///
    /// Reset times alone are not enough: an idle 5-hour session may report no reset
    /// time at all, which used to put it below the weekly window.
    public static func sorted(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        windows.sorted { lhs, rhs in
            switch (lhs.duration, rhs.duration) {
            case (let left?, let right?) where left != right: return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                let left = lhs.resetsAt ?? .distantFuture, right = rhs.resetsAt ?? .distantFuture
                return left != right ? left < right : lhs.label < rhs.label
            }
        }
    }

    /// Reads a window length from names like "session (5h)", "weekly (7d)",
    /// "30d", "1w", "monthly" or "daily". Nil when the name does not say.
    public static func duration(of name: String) -> TimeInterval? {
        let text = name.lowercased()
        let units: [(suffixes: [String], seconds: TimeInterval)] = [
            (["mo", "mon", "month", "months"], 30 * 86_400),
            (["w", "wk", "week", "weeks"], 7 * 86_400),
            (["d", "day", "days"], 86_400),
            (["h", "hr", "hrs", "hour", "hours"], 3_600),
            (["m", "min", "mins", "minute", "minutes"], 60)
        ]
        // The last "<number><unit>" in the name wins: "Opus (7d)" → 7 days.
        let tokens = text.split { !$0.isLetter && !$0.isNumber && $0 != "." }
        for token in tokens.reversed() {
            let digits = token.prefix { $0.isNumber || $0 == "." }
            guard !digits.isEmpty, let value = Double(digits) else { continue }
            var unit = String(token.dropFirst(digits.count))
            if unit.isEmpty, let next = tokens.drop(while: { $0 != token }).dropFirst().first { unit = String(next) }
            if let match = units.first(where: { $0.suffixes.contains(unit) }) { return value * match.seconds }
        }
        let words: [(String, TimeInterval)] = [
            ("hourly", 3_600), ("session", 5 * 3_600), ("daily", 86_400), ("day", 86_400),
            ("weekly", 7 * 86_400), ("week", 7 * 86_400), ("monthly", 30 * 86_400), ("month", 30 * 86_400)
        ]
        return words.first { text.contains($0.0) }?.1
    }

    /// Merges several connections of one provider, keeping the busiest value per window.
    public static func merge(_ lists: [[QuotaWindow]]) -> [QuotaWindow] {
        var merged: [String: QuotaWindow] = [:]
        var order: [String] = []
        for window in lists.joined() {
            if let existing = merged[window.label] {
                if window.usedPercent > existing.usedPercent { merged[window.label] = window }
            } else {
                merged[window.label] = window
                order.append(window.label)
            }
        }
        return sorted(order.compactMap { merged[$0] })
    }

    static func usedPercent(_ quota: [String: Any]) -> Double? {
        func number(_ key: String) -> Double? { (quota[key] as? NSNumber)?.doubleValue }
        if let remaining = number("remainingPercentage") { return 100 - remaining }
        if let used = number("used"), let total = number("total"), total > 0 { return used / total * 100 }
        return nil
    }

    static func label(for name: String) -> String {
        if let open = name.lastIndex(of: "("), let close = name.lastIndex(of: ")"), open < close {
            let inner = name[name.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !inner.isEmpty { return inner }
        }
        return name.capitalized
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
