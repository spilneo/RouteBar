import Foundation

/// One connected account of a provider, with its own limits.
public struct ProviderAccount: Identifiable, Sendable, Equatable {
    public let id: String
    /// Unique within the provider: the account email or connection name, numbered when repeated.
    public let name: String
    public let isActive: Bool
    public let quotas: [QuotaWindow]

    public init(id: String, name: String, isActive: Bool, quotas: [QuotaWindow] = []) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.quotas = quotas
    }
}

/// A connected provider as RouteBar shows it: one tile per provider id.
public struct ProviderTile: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// At least one connection for this provider is enabled and healthy.
    public let isActive: Bool
    /// Subscription windows, busiest value across the provider's connections.
    public let quotas: [QuotaWindow]
    /// Every connection of this provider, in OmniRoute's order.
    public let accounts: [ProviderAccount]

    public init(id: String, name: String, isActive: Bool, quotas: [QuotaWindow] = [], accounts: [ProviderAccount] = []) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.quotas = quotas
        self.accounts = accounts
    }

    public var activeAccounts: Int { accounts.filter(\.isActive).count }
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
    /// Groups connections by provider, keeping first-seen order, naming each
    /// provider from the catalog and attaching quotas of its usable connections.
    /// Each tile also lists its accounts, so several logins of one provider stay apart.
    public static func tiles(
        connections: [Connection],
        catalog: [String: CatalogProvider],
        quotas: [String: [QuotaWindow]] = [:]
    ) -> [ProviderTile] {
        var order: [String] = []
        var grouped: [String: [Connection]] = [:]
        for connection in connections where !connection.provider.isEmpty {
            if grouped[connection.provider] == nil { order.append(connection.provider) }
            grouped[connection.provider, default: []].append(connection)
        }
        return order.map { id in
            let members = grouped[id] ?? []
            let usable = members.filter(\.isUsable)
            return ProviderTile(
                id: id,
                name: displayName(for: id, catalog: catalog),
                isActive: !usable.isEmpty,
                quotas: Quotas.merge(usable.compactMap { $0.id.flatMap { quotas[$0] } }),
                accounts: accounts(members, quotas: quotas)
            )
        }
    }

    /// Names each connection by its account, else its connection name, and
    /// numbers repeats ("Claude (imported)", "Claude (imported) 2").
    static func accounts(_ connections: [Connection], quotas: [String: [QuotaWindow]]) -> [ProviderAccount] {
        var used: [String: Int] = [:]
        return connections.enumerated().map { index, connection in
            let base = [connection.account, connection.name]
                .lazy.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "Account \(index + 1)"
            let count = (used[base] ?? 0) + 1
            used[base] = count
            let id = connection.id ?? "\(connection.provider)#\(index)"
            return ProviderAccount(
                id: id,
                name: count == 1 ? base : "\(base) \(count)",
                isActive: connection.isUsable,
                quotas: connection.isUsable ? connection.id.flatMap { quotas[$0] } ?? [] : []
            )
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

    /// Time left until a moment, in its two largest units: "2d 7h", "4h 6m", "12m".
    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(Int(date.timeIntervalSince(now)), 0)
        let days = seconds / 86_400, hours = seconds % 86_400 / 3_600, minutes = seconds % 3_600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
