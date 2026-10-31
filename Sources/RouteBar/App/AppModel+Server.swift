import AppKit
import Foundation

/// Turning the OmniRoute endpoint on and off.
extension AppModel {
    func setServer(on enabled: Bool) {
        if isRemote {
            if enabled {
                // Nothing on this Mac can start a process on another one.
                show("Start OmniRoute on \(serverLabel), RouteBar connects as soon as it answers")
            } else if confirmRemoteStop() {
                Task { await stopServer() }
            }
            return
        }
        preferences.wantsServer = enabled
        if enabled { startServer() } else { Task { await stopServer() } }
    }

    func startServer() {
        guard !server.isOn, !isRemote else { return }
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
        do {
            try await client.shutdown()
        } catch where isRemote {
            server = .running
            problem = "Could not stop \(serverLabel): \(error.localizedDescription)"
            return
        } catch {}
        if !isRemote { process.stop() }
        await refresh()
    }

    /// A remote server cannot be started again from RouteBar, so stopping it is confirmed.
    private func confirmRemoteStop() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Stop OmniRoute on \(serverLabel)?"
        alert.informativeText = "Every app using this server loses its endpoint. RouteBar cannot start a remote server again, "
            + "so it has to be started on that machine."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop Server")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
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
            update(\.server, to: online ? .running : .stopped)
        }
    }
}
