import Foundation

/// Turning the OmniRoute endpoint on and off.
extension AppModel {
    func setServer(on enabled: Bool) {
        preferences.wantsServer = enabled
        if enabled { startServer() } else { Task { await stopServer() } }
    }

    func startServer() {
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

    func stopServer() async {
        server = .stopping
        transitionStarted = Date()
        // Shutting down through the API also covers an OmniRoute started outside RouteBar.
        try? await client.shutdown()
        process.stop()
        await refresh()
    }

    /// Reconciles the believed state with what the health check saw, giving a
    /// starting server time to boot (npx may still be downloading OmniRoute).
    func updateServerState(online: Bool) {
        let elapsed = transitionStarted.map { Date().timeIntervalSince($0) } ?? .infinity
        switch (server, online) {
        case (.starting, false) where elapsed < 300 && process.isRunning:
            return
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
}
