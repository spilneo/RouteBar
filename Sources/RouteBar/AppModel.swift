import AppKit
import Observation
import RouteBarKit
import ServiceManagement

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
@MainActor
@Observable
final class AppModel {
    private(set) var server: ServerState = .stopped
    private(set) var tiles: [ProviderTile] = []
    private(set) var models: [String] = []
    private(set) var usage: [UsagePoint] = []
    private(set) var summary: Analytics.Summary?
    private(set) var problem: String?
    private(set) var notice: String?
    var range: UsageRange = .week {
        didSet { Task { await refreshAnalytics() } }
    }

    var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
    }

    var opensAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                show("Could not change Open at Login: \(error.localizedDescription)")
            }
        }
    }

    var isPanelVisible = false {
        didSet { if isPanelVisible { Task { await refresh() } } }
    }

    private let client = OmniRouteClient()
    private let process = ServerProcess()
    private let defaults = UserDefaults.standard
    private var catalog: [String: CatalogProvider] = [:]
    private var catalogFetchedAt: Date?
    private var importAttempted: Set<LocalLogins.Tool> = []
    private var pollTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var transitionStarted: Date?

    private enum Keys {
        static let wantsServer = "wantsServer"
        static let autoImport = "autoImportLogins"
    }

    init() {
        defaults.register(defaults: [Keys.wantsServer: true, Keys.autoImport: true])
        autoImport = defaults.bool(forKey: Keys.autoImport)
    }

    var logURL: URL { process.logURL }

    // MARK: - Lifecycle

    func launch() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            if await !client.isOnline(), defaults.bool(forKey: Keys.wantsServer) {
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

    // MARK: - Server

    func setServer(on enabled: Bool) {
        defaults.set(enabled, forKey: Keys.wantsServer)
        if enabled { startServer() } else { Task { await stopServer() } }
    }

    private func startServer() {
        guard !server.isOn else { return }
        do {
            try process.start()
            server = .starting
            transitionStarted = Date()
            problem = nil
        } catch {
            server = .stopped
            problem = error.localizedDescription
        }
    }

    private func stopServer() async {
        server = .stopping
        transitionStarted = Date()
        // Shutting down through the API also covers an OmniRoute started outside RouteBar.
        try? await client.shutdown()
        process.stop()
        await refresh()
    }

    // MARK: - Refresh

    func refresh() async {
        let online = await client.isOnline()
        updateServerState(online: online)
        guard online else {
            tiles = []
            models = []
            return
        }

        do {
            if catalogFetchedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                catalog = await (try? client.catalog()) ?? catalog
                catalogFetchedAt = Date()
            }
            let connections = try await client.connections()
            let newTiles = Dashboard.tiles(connections: connections, catalog: catalog)
            let active = Set(newTiles.filter(\.isActive).map(\.id))
            let entries = try await client.models()
            tiles = newTiles
            models = Dashboard.models(entries, activeProviders: active, catalog: catalog)
            problem = nil
            await importLocalLogins(existing: Set(newTiles.map(\.id)))
        } catch {
            problem = error.localizedDescription
        }
        await refreshAnalytics()
    }

    private func refreshAnalytics() async {
        guard server == .running, let analytics = try? await client.analytics(range: range.rawValue) else { return }
        summary = analytics.summary
        usage = Dashboard.series(analytics.dailyTrend ?? [], days: range.days)
    }

    private func updateServerState(online: Bool) {
        let elapsed = transitionStarted.map { Date().timeIntervalSince($0) } ?? .infinity
        switch (server, online) {
        case (.starting, false) where elapsed < 300 && process.isRunning:
            return // npx may still be downloading OmniRoute.
        case (.starting, false):
            server = .stopped
            problem = "OmniRoute did not start. See the log for details."
        case (.stopping, true) where elapsed < 15:
            return
        case (.stopping, true):
            server = .running
            problem = "OmniRoute is still running."
        default:
            server = online ? .running : .stopped
        }
    }

    // MARK: - Local logins

    /// Hands Claude Code and Codex subscription logins to OmniRoute once per
    /// session, only for providers that have no connection yet.
    private func importLocalLogins(existing: Set<String>) async {
        guard autoImport else { return }
        for tool in LocalLogins.Tool.allCases where !existing.contains(tool.providerID) && !importAttempted.contains(tool) {
            importAttempted.insert(tool)
            let credentials = await Task.detached(priority: .utility) { LocalLogins.credentials(for: tool) }.value
            guard let credentials else { continue }
            do {
                let outcome = switch tool {
                case .claude: try await client.importClaudeLogin(credentials)
                case .codex: try await client.importCodexLogin(credentials)
                }
                if outcome == .imported { show("Connected your \(tool.displayName) login") }
            } catch {
                show("Could not import the \(tool.displayName) login: \(error.localizedDescription)")
            }
        }
    }

    func retryImports() {
        importAttempted.removeAll()
        Task { await refresh() }
    }

    // MARK: - Notices

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
}
