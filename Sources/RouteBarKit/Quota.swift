import Foundation

/// One subscription limit window, such as Claude's 5-hour session or weekly cap.
public struct QuotaWindow: Identifiable, Sendable, Equatable {
    /// Short label: the text in parentheses of OmniRoute's name ("session (5h)" → "5h").
    public let label: String
    /// Share of the window already used, 0…100.
    public let usedPercent: Double
    public let resetsAt: Date?

    public var id: String { label }

    public init(label: String, usedPercent: Double, resetsAt: Date?) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
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
            return QuotaWindow(label: label(for: name), usedPercent: min(max(used, 0), 100), resetsAt: reset)
        }
        // The window that resets soonest first: "5h" before "7d".
        return windows.sorted { ($0.resetsAt ?? .distantFuture, $0.label) < ($1.resetsAt ?? .distantFuture, $1.label) }
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
        return order.compactMap { merged[$0] }
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
