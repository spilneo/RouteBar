import Foundation
import RouteBarKit

/// The Internet endpoint: OmniRoute's Cloudflare quick tunnel, plus its
/// `REQUIRE_API_KEY` flag, which decides whether that public address needs a key.
///
/// RouteBar opens the tunnel whenever Internet is chosen and the local server
/// runs, because OmniRoute does not reopen it after a restart. It only closes a
/// tunnel when the user moves away from Internet, so a tunnel opened from the
/// dashboard is left alone.
extension AppModel {
    /// Seconds before RouteBar retries a tunnel that failed to open on its own.
    private static let tunnelRetryDelay: TimeInterval = 60

    /// Applies the Endpoint choice from Settings.
    func setEndpointHost(_ host: EndpointHost) {
        let previous = preferences.endpointHost
        guard host != previous else { return }
        preferences.endpointHost = host
        update(\.tunnelError, to: nil)
        if host == .tunnel {
            Task { await openTunnelIfNeeded(force: true) }
        } else if previous == .tunnel {
            Task { await closeTunnel() }
        }
        if host != .localhost { Task { await refreshRequiresAPIKey(force: true) } }
    }

    /// The tunnel is being opened, so there is no public address to show yet.
    var isTunnelPending: Bool {
        guard preferences.endpointHost == .tunnel, !isRemote, server == .running, tunnelRoot == nil else { return false }
        return isChangingTunnel || tunnel?.phase == .starting
    }

    /// The tunnel's public root while it is up.
    var tunnelRoot: URL? { isRemote ? nil : tunnel?.publicRoot }

    /// Forgets everything known about the tunnel, for a new server target.
    func resetTunnelState() {
        tunnel = nil
        isChangingTunnel = false
        tunnelError = nil
        requiresAPIKey = nil
        tunnelCheckedAt = nil
        tunnelOpenAttemptAt = nil
        requiresAPIKeyCheckedAt = nil
        apiKeyState.reset()
    }

    /// Polls the tunnel while Internet is chosen and reopens it when it is down,
    /// for example after OmniRoute restarted.
    func refreshTunnel() async {
        guard !isRemote, server == .running, preferences.endpointHost == .tunnel else {
            update(\.tunnel, to: nil)
            return
        }
        if !isChangingTunnel, tunnel?.phase == .starting || isStale(tunnelCheckedAt, after: 15) {
            let client = client, generation = generation
            let status = try? await client.tunnelStatus()
            guard generation == self.generation else { return }
            tunnelCheckedAt = Date()
            update(\.tunnel, to: status)
        }
        await openTunnelIfNeeded(force: false)
    }

    /// Opens the tunnel when Internet is chosen and it is not up. Without `force`
    /// a recent failure is not retried, so a broken setup is not hammered.
    func openTunnelIfNeeded(force: Bool) async {
        guard !isRemote, server == .running, preferences.endpointHost == .tunnel, !isChangingTunnel,
              tunnel?.running != true, tunnel?.phase != .starting else { return }
        guard force || isStale(tunnelOpenAttemptAt, after: Self.tunnelRetryDelay) else { return }

        let client = client, generation = generation
        isChangingTunnel = true
        tunnelOpenAttemptAt = Date()
        let result: Result<TunnelStatus?, Error>
        do { result = try await .success(client.setTunnel(enabled: true)) } catch { result = .failure(error) }
        guard generation == self.generation else { return }
        isChangingTunnel = false
        tunnelCheckedAt = Date()

        switch result {
        case .success(let status):
            update(\.tunnel, to: status)
            update(\.tunnelError, to: status?.publicRoot == nil ? status?.lastError ?? "OmniRoute opened no public address." : nil)
            // Internet may have been deselected while Cloudflare was answering.
            if preferences.endpointHost != .tunnel {
                await closeTunnel()
            } else if let host = status?.publicRoot?.host {
                show("Public endpoint ready at \(host)")
            }
        case .failure(let error):
            update(\.tunnelError, to: error.localizedDescription)
        }
    }

    /// Closes the tunnel. Waits for an opening in flight, which then closes it itself.
    func closeTunnel() async {
        guard !isRemote, !isChangingTunnel else { return }
        let client = client, generation = generation
        isChangingTunnel = true
        let status = try? await client.setTunnel(enabled: false)
        guard generation == self.generation else { return }
        isChangingTunnel = false
        update(\.tunnel, to: status)
        tunnelCheckedAt = Date()
        // Internet may have been chosen again while the tunnel was closing.
        if preferences.endpointHost == .tunnel { await openTunnelIfNeeded(force: true) }
    }

    /// Reads `REQUIRE_API_KEY` while the endpoint reaches beyond this Mac.
    func refreshRequiresAPIKey(force: Bool = false) async {
        guard !isRemote, server == .running, preferences.endpointHost != .localhost else { return }
        guard force || isStale(requiresAPIKeyCheckedAt, after: 60) else { return }
        let client = client, generation = generation
        let required = try? await client.requiresAPIKey()
        guard generation == self.generation else { return }
        requiresAPIKeyCheckedAt = Date()
        update(\.requiresAPIKey, to: required)
        await refreshAPIKeys()
    }

    func setRequiresAPIKey(_ enabled: Bool) {
        let client = client, generation = generation
        Task {
            do {
                try await client.setRequiresAPIKey(enabled)
                guard generation == self.generation else { return }
                await refreshRequiresAPIKey(force: true)
                // RouteBar needs a key for the model list from now on, and the user one to copy.
                if enabled, apiKeyState.copyable.isEmpty { apiKeyState.modelsKey = await ownAPIKey(client: client, announce: false) }
                show(enabled ? "Every app now needs an OmniRoute API key. Copy one in Settings." : "Apps can use the endpoint without a key")
            } catch {
                guard generation == self.generation else { return }
                show("Could not change the API key requirement: \(error.localizedDescription)")
            }
        }
    }
}
