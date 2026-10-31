import AppKit
import Observation
import RouteBarKit

enum ServerState: Equatable {
    case stopped
    case starting
    case running
    case stopping

    var isOn: Bool { self == .running || self == .starting }
}

enum UsageRange: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
    var label: String { self == .week ? "7D" : "30D" }
}

/// Everything the panel shows, refreshed from OmniRoute on a short poll.
///
/// Server lifecycle lives in `AppModel+Server.swift`, login import in
/// `AppModel+Logins.swift` and remote servers in `AppModel+Remote.swift`.
/// This file owns the data and the refresh schedule.
@MainActor
@Observable
final class AppModel {
    // MARK: Published state

    var server: ServerState = .stopped
    private(set) var tiles: [ProviderTile] = []
    private(set) var models: [String] = []
    private(set) var usage: [UsagePoint] = []
    private(set) var summary: Analytics.Summary?
    private(set) var version: ServerVersion?
    private(set) var activeRequests = 0
    var problem: String?
    private(set) var notice: String?
    var isImporting = false
    var showsSettings = false
    /// The provider tile unfolded to list its accounts.
    var expandedProvider: String?
    /// This Mac's LAN address, set only once OmniRoute answered on it.
    private(set) var lanAddress: String?

    var range: UsageRange = .week {
        didSet { Task { await refreshAnalytics() } }
    }

    var isPanelVisible = false {
        didSet { if isPanelVisible { Task { await refresh(panelOpened: true) } } }
    }

    let preferences = Preferences()

    // MARK: Collaborators and caches

    private(set) var client: OmniRouteClient
    /// Bumped whenever the server target changes, so late answers from the old one are dropped.
    private(set) var generation = 0
    let process = ServerProcess()
    var catalog: [String: CatalogProvider] = [:]
    var importedThisSession = false
    var transitionStarted: Date?
    private var connections: [Connection] = []
    private var quotas: [String: [QuotaWindow]] = [:]
    private var catalogFetchedAt: Date?
    private var quotasFetchedAt: Date?
    private var versionFetchedAt: Date?
    private var pollTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lanCheckedAt: Date?
    private var lanCandidate: String?

    var logURL: URL { process.logURL }

    init() {
        client = Self.makeClient(preferences: preferences)
        ProviderIcons.shared.use(client)
    }

    // MARK: - Server target

    var isRemote: Bool { !client.isLocal }

    /// The server root as apps elsewhere should address it.
    var serverRoot: URL {
        guard client.isLocal else { return client.baseURL }
        let host = preferences.endpointHost == .network ? lanAddress ?? "localhost" : "localhost"
        return URL(string: "http://\(host):\(OmniRoute.port)")!
    }

    var endpoint: String { ServerAddress.endpoint(for: serverRoot) }
    var serverLabel: String { ServerAddress.label(for: client.baseURL) }
    var dashboardURL: URL { isRemote ? client.baseURL.appendingPathComponent("dashboard") : OmniRoute.dashboardURL }
    var providersURL: URL { isRemote ? client.baseURL.appendingPathComponent("dashboard/providers") : OmniRoute.providersURL }

    static func makeClient(preferences: Preferences) -> OmniRouteClient {
        if preferences.usesRemote, let remote = preferences.remote {
            let token = Preferences.keychain.read(remote.url.absoluteString)
            return OmniRouteClient(baseURL: remote.url, cliToken: nil, accessToken: token, timeout: 6)
        }
        return OmniRouteClient()
    }

    /// Points every call at the server chosen in Settings and starts over with fresh data.
    func applyServerTarget() {
        client = Self.makeClient(preferences: preferences)
        generation += 1
        ProviderIcons.shared.use(client)
        server = .stopped
        transitionStarted = nil
        tiles = []
        models = []
        usage = []
        summary = nil
        version = nil
        activeRequests = 0
        problem = nil
        catalog = [:]
        connections = []
        quotas = [:]
        catalogFetchedAt = nil
        quotasFetchedAt = nil
        versionFetchedAt = nil
        Task { await refresh(panelOpened: true) }
    }

    // MARK: - Lifecycle

    func launch() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if !isRemote, await !client.isOnline(), preferences.wantsServer {
                startServer()
            }
            var tick = 0
            while !Task.isCancelled {
                // Fast while the panel is open or the server is changing state, slow otherwise.
                if isPanelVisible || server == .starting || server == .stopping || tick % 5 == 0 {
                    await refresh()
                }
                tick += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func terminate() {
        pollTask?.cancel()
        process.stopAndWait()
    }

    // MARK: - Refresh

    func refresh(panelOpened: Bool = false) async {
        let client = client, generation = generation
        let online = await client.isOnline()
        guard generation == self.generation else { return }
        updateServerState(online: online)
        guard online else {
            update(\.tiles, to: [])
            update(\.models, to: [])
            update(\.activeRequests, to: 0)
            return
        }
        await refreshLANAddress()

        guard await refreshInventory(client: client, generation: generation) else { return }

        let requests = await (try? client.activeRequests()) ?? 0
        guard generation == self.generation else { return }
        update(\.activeRequests, to: requests)
        await refreshAnalytics()
        // Quotas come from the providers themselves, so they are polled sparingly.
        if isStale(quotasFetchedAt, after: panelOpened ? 30 : 90) { await refreshQuotas() }
        if isStale(versionFetchedAt, after: 600) {
            let fetched = try? await client.version()
            guard generation == self.generation else { return }
            update(\.version, to: fetched)
            versionFetchedAt = Date()
        }
    }

    /// Providers and models. Returns false when the server target changed meanwhile.
    private func refreshInventory(client: OmniRouteClient, generation: Int) async -> Bool {
        do {
            if isStale(catalogFetchedAt, after: 60) {
                // A remote access token may not read the catalog; names then fall back to built-ins.
                let fetched = await (try? client.catalog()) ?? catalog
                guard generation == self.generation else { return false }
                update(\.catalog, to: fetched)
                catalogFetchedAt = Date()
            }
            let fetched = try await client.connections()
            let entries = try await client.models()
            guard generation == self.generation else { return false }
            connections = fetched
            let active = Set(fetched.filter(\.isUsable).map(\.provider))
            update(\.models, to: Dashboard.models(entries, activeProviders: active, catalog: catalog))
            rebuildTiles()
            update(\.problem, to: nil)
            if !isRemote, preferences.autoImport, !importedThisSession { await importLogins(includeInteractive: false) }
        } catch {
            guard generation == self.generation else { return false }
            update(\.problem, to: error.localizedDescription)
        }
        return generation == self.generation
    }

    /// Finds this Mac's LAN address and keeps it only if OmniRoute answers there,
    /// which it does when it listens on every interface (its default).
    private func refreshLANAddress() async {
        guard client.isLocal else { return }
        let candidate = NetworkAddress.lanIPv4()
        guard candidate != lanCandidate || isStale(lanCheckedAt, after: 60) else { return }
        lanCandidate = candidate
        lanCheckedAt = Date()
        guard let candidate, let url = URL(string: "http://\(candidate):\(OmniRoute.port)") else {
            update(\.lanAddress, to: nil)
            return
        }
        let reachable = await OmniRouteClient(baseURL: url, cliToken: nil, timeout: 1.5).isOnline()
        update(\.lanAddress, to: reachable ? candidate : nil)
    }

    func refreshAnalytics() async {
        let client = client, generation = generation
        guard server == .running, let analytics = try? await client.analytics(range: range.rawValue),
              generation == self.generation else { return }
        update(\.summary, to: analytics.summary)
        update(\.usage, to: Dashboard.series(analytics.dailyTrend ?? [], days: range.days))
    }

    private func refreshQuotas() async {
        quotasFetchedAt = Date()
        let ids = connections.filter(\.isUsable).compactMap(\.id)
        let client = client, generation = generation
        let results = await withTaskGroup(of: (String, [QuotaWindow]?).self) { group in
            for id in ids {
                group.addTask { await (id, try? client.quotas(connectionID: id)) }
            }
            var collected: [String: [QuotaWindow]] = [:]
            for await (id, windows) in group {
                if let windows { collected[id] = windows }
            }
            return collected
        }
        guard generation == self.generation else { return }
        quotas = results
        rebuildTiles()
    }

    private func rebuildTiles() {
        update(\.tiles, to: Dashboard.tiles(connections: connections, catalog: catalog, quotas: quotas))
    }

    /// Observation redraws every view that read a property on each assignment,
    /// even an equal one. The poll re-assigns mostly unchanged data every two
    /// seconds, so only real changes are written.
    func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>, to value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    #if DEBUG
        /// Snapshot fixture: many providers, one of them with several accounts.
        func showDemoTiles() {
            let soon = Date().addingTimeInterval(3 * 3_600), later = Date().addingTimeInterval(4 * 86_400)
            func windows(_ session: Double, _ week: Double) -> [QuotaWindow] {
                [QuotaWindow(label: "5h", usedPercent: session, resetsAt: soon), QuotaWindow(label: "7d", usedPercent: week, resetsAt: later)]
            }
            var connections = [
                Connection(id: "c1", provider: "claude", name: "Claude (imported)", isActive: true, account: "me@example.com"),
                Connection(id: "c2", provider: "claude", name: "Claude (imported)", isActive: true, account: "work@example.com"),
                Connection(id: "c3", provider: "claude", name: "Team", isActive: true),
                Connection(id: "c4", provider: "claude", name: "Old", isActive: false)
            ]
            for (index, id) in ["codex", "cursor", "gemini", "kiro", "github", "openai", "anthropic", "antigravity", "grok-cli"].enumerated() {
                connections.append(Connection(id: "p\(index)", provider: id, isActive: index != 5))
            }
            let quotas = ["c1": windows(42, 18), "c2": windows(83, 61), "c3": windows(97, 40), "p0": windows(12, 55)]
            tiles = Dashboard.tiles(connections: connections, catalog: catalog, quotas: quotas)
            expandedProvider = "claude"
        }
    #endif

    private func isStale(_ date: Date?, after seconds: TimeInterval) -> Bool {
        date.map { Date().timeIntervalSince($0) > seconds } ?? true
    }

    // MARK: - Notices and actions

    func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice = nil }
        }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }
}
