import Foundation

/// Finds the subscription logins that Claude Code and the Codex CLI keep on this
/// Mac, so RouteBar can hand them to OmniRoute without the user uploading files.
///
/// Credentials are only read, never written or logged, and are returned as the
/// raw JSON that OmniRoute's own import endpoints accept.
public enum LocalLogins {
    public enum Tool: String, CaseIterable, Sendable {
        case claude
        case codex

        /// The OmniRoute provider id the login becomes.
        public var providerID: String { rawValue }

        public var displayName: String {
            switch self {
            case .claude: "Claude Code"
            case .codex: "Codex"
            }
        }
    }

    public static func credentials(
        for tool: Tool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        keychain: () -> Data? = claudeKeychainItem
    ) -> Data? {
        switch tool {
        case .claude:
            let directory = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".claude")
            let file = try? Data(contentsOf: directory.appendingPathComponent(".credentials.json"))
            return [file, keychain()].lazy.compactMap(\.self).first(where: isClaudeLogin)
        case .codex:
            let directory = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".codex")
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("auth.json")),
                  isCodexLogin(data) else { return nil }
            return data
        }
    }

    /// `{"claudeAiOauth": {"accessToken": …, "refreshToken": …}}`
    public static func isClaudeLogin(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any] else { return false }
        return nonEmpty(oauth["accessToken"]) && nonEmpty(oauth["refreshToken"])
    }

    /// A ChatGPT sign-in with the tokens OmniRoute requires, not an API-key-only file.
    public static func isCodexLogin(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any] else { return false }
        return nonEmpty(tokens["id_token"]) && nonEmpty(tokens["access_token"]) && nonEmpty(tokens["refresh_token"])
    }

    /// Claude Code on macOS keeps its login in the Keychain item
    /// "Claude Code-credentials", written through `/usr/bin/security`. Reading it
    /// through the same tool keeps the item's access list satisfied, so macOS
    /// does not ask again after every RouteBar update.
    public static func claudeKeychainItem() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let trimmed = data.trimmingTrailingNewlines()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmpty(_ value: Any?) -> Bool {
        (value as? String).map { !$0.isEmpty } ?? false
    }
}

extension Data {
    func trimmingTrailingNewlines() -> Data {
        var copy = self
        while let last = copy.last, last == 0x0a || last == 0x0d {
            copy.removeLast()
        }
        return copy
    }
}
