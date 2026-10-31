import Foundation
import Observation
import ServiceManagement

/// The few settings RouteBar has, each shown as an icon button in the footer.
@MainActor
@Observable
final class Preferences {
    private enum Keys {
        static let wantsServer = "wantsServer"
        static let autoImport = "autoImportLogins"
    }

    private let defaults: UserDefaults

    /// Keep the endpoint on across launches. Turning it off is remembered.
    var wantsServer: Bool {
        didSet { defaults.set(wantsServer, forKey: Keys.wantsServer) }
    }

    /// Connect logins found on this Mac without asking.
    var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
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
