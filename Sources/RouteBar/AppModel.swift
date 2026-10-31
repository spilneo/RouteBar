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
    private var importedThisSession = false
    private var importing = false
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
            if autoImport, !importedThisSession { await importLogins(includeInteractive: false) }
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

    /// Runs every importer OmniRoute offers, then names what was added using
    /// OmniRoute's own provider catalog. Automatic runs skip importers that can
    /// show a macOS permission prompt, a manual run includes them.
    private func importLogins(includeInteractive: Bool) async {
        guard !importing else { return }
        importing = true
        importedThisSession = true
        defer { importing = false }

        let before = await Set(((try? client.connections()) ?? []).map(\.provider))
        let importer = LoginImporter(client: client)
        // Off the main actor: reading a Keychain item blocks on a child process.
        let failures = await Task.detached(priority: .utility) {
            await importer.run(connected: before, includeInteractive: includeInteractive)
        }.value
        let after = await (try? client.connections()) ?? []
        let added = Dashboard.tiles(connections: after.filter { !before.contains($0.provider) }, catalog: catalog)

        if !added.isEmpty {
            show("Connected " + ListFormatter.localizedString(byJoining: added.map(\.name)))
            await refresh()
        } else if let failure = failures.first {
            let name = Dashboard.displayName(for: failure.source, catalog: catalog)
            show("Could not import the \(name) login: \(failure.message)")
        } else if includeInteractive {
            show("No new logins found on this Mac")
        }
    }

    func importLoginsNow() {
        Task { await importLogins(includeInteractive: true) }
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
