import Foundation

/// A connected provider as RouteBar shows it: one tile per provider id.
public struct ProviderTile: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// At least one connection for this provider is enabled and healthy.
    public let isActive: Bool

    public init(id: String, name: String, isActive: Bool) {
        self.id = id
        self.name = name
        self.isActive = isActive
    }
}

/// One bar of the usage chart.
public struct UsagePoint: Identifiable, Sendable, Equatable {
    public let date: Date
    public let requests: Int
    public let tokens: Int
    public var id: Date { date }

    public init(date: Date, requests: Int, tokens: Int) {
        self.date = date
        self.requests = requests
        self.tokens = tokens
    }
}

/// Pure transformations from OmniRoute responses to what the panel renders.
public enum Dashboard {
    /// Groups connections by provider, keeping first-seen order and naming each
    /// provider from the catalog when it knows the id.
    public static func tiles(connections: [Connection], catalog: [String: CatalogProvider]) -> [ProviderTile] {
        var order: [String] = []
        var active: [String: Bool] = [:]
        for connection in connections where !connection.provider.isEmpty {
            if active[connection.provider] == nil { order.append(connection.provider) }
            active[connection.provider] = (active[connection.provider] ?? false) || connection.isUsable
        }
        return order.map { id in
            ProviderTile(id: id, name: displayName(for: id, catalog: catalog), isActive: active[id] ?? false)
        }
    }

    public static func displayName(for id: String, catalog: [String: CatalogProvider]) -> String {
        if let name = catalog[id]?.provider?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != id {
            return name
        }
        let known = ["claude": "Claude Code", "codex": "Codex", "cursor": "Cursor", "gemini": "Gemini",
                     "openai": "OpenAI", "anthropic": "Anthropic", "github": "Copilot", "kiro": "Kiro"]
        if let name = known[id] { return name }
        return id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Model ids served by providers that have an active connection. A model
    /// qualifies when its `owned_by` is such a provider or when the catalog lists
    /// it under one. Order follows OmniRoute, duplicates are dropped.
    public static func models(
        _ models: [ModelEntry],
        activeProviders: Set<String>,
        catalog: [String: CatalogProvider]
    ) -> [String] {
        guard !activeProviders.isEmpty else { return [] }
        let catalogIDs = Set(activeProviders.flatMap { catalog[$0]?.models?.map(\.id) ?? [] })
        var seen = Set<String>()
        return models.compactMap { model in
            let owned = model.ownedBy.map(activeProviders.contains) ?? false
            guard owned || catalogIDs.contains(model.id), seen.insert(model.id).inserted else { return nil }
            return model.id
        }
    }

    /// Case-insensitive search where every whitespace-separated term must match.
    public static func filter(_ models: [String], query: String) -> [String] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return models }
        return models.filter { id in
            let haystack = id.lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// One point per calendar day ending today, filling days without traffic with zero.
    public static func series(
        _ trend: [Analytics.Day],
        days: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [UsagePoint] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var byDate: [String: Analytics.Day] = [:]
        for day in trend {
            byDate[day.date] = day
        }

        let start = calendar.startOfDay(for: today)
        return (0..<max(days, 1)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let day = byDate[formatter.string(from: date)]
            return UsagePoint(date: date, requests: day?.requests ?? 0, tokens: day?.totalTokens ?? 0)
        }
    }

    /// Compact counts: 950, 1.2K, 3.4M.
    public static func compact(_ value: Int) -> String {
        let magnitude = abs(Double(value))
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (scale, suffix) in units where magnitude >= scale {
            let scaled = Double(value) / scale
            let text = scaled >= 100 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + suffix
        }
        return String(value)
    }
}
