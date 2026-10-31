import Foundation
import Observation
import RouteBarKit
import ServiceManagement

/// A remote OmniRoute that RouteBar signed in to. The access token itself lives in the Keychain.
struct RemoteServer: Codable, Equatable {
    var url: URL
    /// The token's name and scope as the server reported them.
    var tokenName: String?
    var scope: String?
}

/// Who the endpoint of a server on this Mac is meant for. Raw values are stored.
enum EndpointHost: String, CaseIterable, Identifiable {
    /// `localhost`: apps on this Mac only.
    case localhost
    /// This Mac's LAN address, so the URL also works from other devices.
    case network
    /// A Cloudflare quick tunnel opened by OmniRoute: a public https address.
    case tunnel

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localhost: "This Mac"
        case .network: "Network"
        case .tunnel: "Internet"
        }
    }
}

/// RouteBar's settings, shown on the Settings screen.
@MainActor
@Observable
final class Preferences {
    private enum Keys {
        static let wantsServer = "wantsServer"
        static let autoImport = "autoImportLogins"
        static let endpointHost = "endpointHost"
        static let remote = "remoteServer"
        static let usesRemote = "usesRemoteServer"
    }

    static let keychain = Keychain(service: "com.spilneo.RouteBar.remote")

    private let defaults: UserDefaults

    /// Keep the endpoint on across launches. Turning it off is remembered.
    var wantsServer: Bool {
        didSet { defaults.set(wantsServer, forKey: Keys.wantsServer) }
    }

    /// Connect logins found on this Mac without asking.
    var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
    }

    var endpointHost: EndpointHost {
        didSet { defaults.set(endpointHost.rawValue, forKey: Keys.endpointHost) }
    }

    /// The last remote server signed in to, kept so switching back needs no new sign-in.
    var remote: RemoteServer? {
        didSet {
            if let remote, let data = try? JSONEncoder().encode(remote) {
                defaults.set(data, forKey: Keys.remote)
            } else {
                defaults.removeObject(forKey: Keys.remote)
            }
        }
    }

    /// Manage `remote` instead of the OmniRoute on this Mac.
    var usesRemote: Bool {
        didSet { defaults.set(usesRemote, forKey: Keys.usesRemote) }
    }

    /// Mirrors the login item registration. Read back after every change
    /// because macOS may refuse or require approval in System Settings.
    private(set) var opensAtLogin: Bool
    private(set) var loginItemError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.wantsServer: true, Keys.autoImport: true])
        wantsServer = defaults.bool(forKey: Keys.wantsServer)
        autoImport = defaults.bool(forKey: Keys.autoImport)
        endpointHost = defaults.string(forKey: Keys.endpointHost).flatMap(EndpointHost.init(rawValue:)) ?? .network
        let remote = defaults.data(forKey: Keys.remote).flatMap { try? JSONDecoder().decode(RemoteServer.self, from: $0) }
        self.remote = remote
        usesRemote = remote != nil && defaults.bool(forKey: Keys.usesRemote)
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}
