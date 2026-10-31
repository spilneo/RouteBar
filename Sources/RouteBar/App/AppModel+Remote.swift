import Foundation
import RouteBarKit

/// Signing in to an OmniRoute on another machine, the way `omniroute connect` does.
extension AppModel {
    enum RemoteCredential {
        /// The server's management password, exchanged once for a scoped access token.
        case password(String)
        /// An existing `oma_` access token, for example from `omniroute tokens create`.
        case token(String)
    }

    enum RemoteError: LocalizedError {
        case invalidAddress
        case notAuthenticated
        case keychain

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "Enter a host or URL, for example 192.168.1.20 or https://ai.example.com."
            case .notAuthenticated: "The server did not accept the token."
            case .keychain: "Could not save the access token in the Keychain."
            }
        }
    }

    /// Validates the credential against the server, stores the token in the
    /// Keychain and switches RouteBar to that server. Throws on any failure and
    /// leaves the current target untouched.
    func connectRemote(address: String, credential: RemoteCredential) async throws {
        guard let url = ServerAddress.normalize(address), !ServerAddress.isLoopback(url) else { throw RemoteError.invalidAddress }

        let token: String
        switch credential {
        case .password(let password):
            let host = Host.current().localizedName ?? "Mac"
            let minted = try await OmniRouteClient(baseURL: url, cliToken: nil, timeout: 10)
                .mintAccessToken(password: password, name: "RouteBar on \(host)")
            token = minted.token
        case .token(let pasted):
            token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let identity = try await OmniRouteClient(baseURL: url, cliToken: nil, accessToken: token, timeout: 10).whoami()
        guard identity.authenticated == true else { throw RemoteError.notAuthenticated }
        guard Preferences.keychain.save(token, for: url.absoluteString) else { throw RemoteError.keychain }

        if let previous = preferences.remote, previous.url != url {
            Preferences.keychain.delete(previous.url.absoluteString)
        }
        preferences.remote = RemoteServer(url: url, tokenName: identity.name, scope: identity.scope)
        preferences.usesRemote = true
        applyServerTarget()
        show("Connected to \(ServerAddress.label(for: url))")
    }

    /// Switches between this Mac and the saved remote server without signing in again.
    func useRemote(_ enabled: Bool) {
        guard enabled != preferences.usesRemote, !enabled || preferences.remote != nil else { return }
        preferences.usesRemote = enabled
        applyServerTarget()
        if !enabled, preferences.wantsServer { startServer() }
    }

    /// Forgets the remote server and its token, then returns to this Mac.
    /// The token stays valid on the server until it is revoked there.
    func forgetRemote() {
        if let remote = preferences.remote { Preferences.keychain.delete(remote.url.absoluteString) }
        preferences.remote = nil
        useRemote(false)
    }
}
