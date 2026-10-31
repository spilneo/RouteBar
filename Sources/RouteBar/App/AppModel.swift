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
/// Server lifecycle lives in `AppModel+Server.swift` and login import in
/// `AppModel+Logins.swift`. This file owns the data and the refresh schedule.
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

    var range: UsageRange = .week {
        didSet { Task { await refreshAnalytics() } }
    }

    var isPanelVisible = false {
        didSet { if isPanelVisible { Task { await refresh(panelOpened: true) } } }
    }

    let preferences = Preferences()

    // MARK: Collaborators and caches

    let client = OmniRouteClient()
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

    var logURL: URL { process.logURL }

    // MARK: - Lifecycle

    func launch() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if await !client.isOnline(), preferences.wantsServer {
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
        let online = await client.isOnline()
        updateServerState(online: online)
        guard online else {
            tiles = []
            models = []
            activeRequests = 0
            return
        }

        do {
            if isStale(catalogFetchedAt, after: 60) {
                catalog = await (try? client.catalog()) ?? catalog
                catalogFetchedAt = Date()
            }
            connections = try await client.connections()
            let active = Set(connections.filter(\.isUsable).map(\.provider))
            let entries = try await client.models()
            models = Dashboard.models(entries, activeProviders: active, catalog: catalog)
            rebuildTiles()
            problem = nil
            if preferences.autoImport, !importedThisSession { await importLogins(includeInteractive: false) }
        } catch {
            problem = error.localizedDescription
        }

        activeRequests = await (try? client.activeRequests()) ?? 0
        await refreshAnalytics()
        // Quotas come from the providers themselves, so they are polled sparingly.
        if isStale(quotasFetchedAt, after: panelOpened ? 30 : 90) { await refreshQuotas() }
        if isStale(versionFetchedAt, after: 600) {
            version = try? await client.version()
            versionFetchedAt = Date()
        }
    }

    func refreshAnalytics() async {
        guard server == .running, let analytics = try? await client.analytics(range: range.rawValue) else { return }
        summary = analytics.summary
        usage = Dashboard.series(analytics.dailyTrend ?? [], days: range.days)
    }

    private func refreshQuotas() async {
        quotasFetchedAt = Date()
        let ids = connections.filter(\.isUsable).compactMap(\.id)
        let client = client
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
        quotas = results
        rebuildTiles()
    }

    private func rebuildTiles() {
        tiles = Dashboard.tiles(connections: connections, catalog: catalog, quotas: quotas)
    }

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
