import Foundation

/// Fixed facts about the local OmniRoute instance RouteBar manages.
public enum OmniRoute {
    public static let port = 20_128
    public static let baseURL = URL(string: "http://127.0.0.1:\(port)")!
    /// The OpenAI-compatible endpoint that third-party apps point at.
    public static let endpoint = "http://localhost:\(port)/v1"
    public static let dashboardURL = URL(string: "http://localhost:\(port)/dashboard")!
    public static let providersURL = URL(string: "http://localhost:\(port)/dashboard/providers")!

    /// OmniRoute's data directory, resolved the same way as its CLI
    /// (`bin/cli/data-dir.mjs`): `DATA_DIR`, then `~/.omniroute` when it exists,
    /// then `$XDG_CONFIG_HOME/omniroute`, then `~/.omniroute`.
    public static func dataDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        if let configured = environment["DATA_DIR"]?.trimmingCharacters(in: .whitespaces), !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        let legacy = home.appendingPathComponent(".omniroute", isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: legacy.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return legacy
        }
        if let xdg = environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespaces), !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("omniroute", isDirectory: true)
        }
        return legacy
    }
}
