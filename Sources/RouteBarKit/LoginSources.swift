import Foundation

/// A place where an AI tool keeps its sign-in on this Mac, and the OmniRoute
/// route that turns it into a provider connection.
///
/// OmniRoute has no single "import everything" route. Each tool has its own
/// importer, so `LoginSource.all` lists every importer OmniRoute offers and
/// `LoginImporter` runs them generically. Supporting another tool is one entry.
public struct LoginSource: Sendable, Identifiable {
    public enum Kind: Sendable {
        /// RouteBar reads the credential (a file, else a Keychain item) and uploads it.
        case upload(files: [LocalFile], keychainService: String? = nil, accepts: Shape, path: String, body: Body)
        /// OmniRoute searches this Mac itself and saves what it finds.
        case serverScan(method: String, path: String, query: [String: String] = [:], json: String? = nil)
        /// OmniRoute reports a login, RouteBar hands the listed fields back to save it.
        case detectThenImport(detect: String, save: String, fields: [String])
        /// OmniRoute lists accounts (`GET`) and imports all of them (`POST`).
        case listThenImport(path: String)
    }

    /// How an uploaded credential is wrapped.
    public enum Body: Sendable {
        /// `{"source": {"kind": "json", "json": …}, "overwriteExisting": false}`
        case sourceJSON
        /// `{"token": "<file contents>"}`
        case tokenText
    }

    /// The minimum a credential must contain before it is worth uploading.
    public enum Shape: Sendable {
        /// `{"claudeAiOauth": {"accessToken", "refreshToken"}}`
        case claudeOAuth
        /// A ChatGPT sign-in: `tokens.id_token`, `access_token` and `refresh_token`.
        case codexTokens
        /// Any JSON object carrying an access token at the top level or under `tokens`.
        case accessToken

        public func accepts(_ data: Data) -> Bool {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            func has(_ value: Any?) -> Bool { (value as? String).map { !$0.isEmpty } ?? false }
            switch self {
            case .claudeOAuth:
                guard let oauth = object["claudeAiOauth"] as? [String: Any] else { return false }
                return has(oauth["accessToken"]) && has(oauth["refreshToken"])
            case .codexTokens:
                guard let tokens = object["tokens"] as? [String: Any] else { return false }
                return has(tokens["id_token"]) && has(tokens["access_token"]) && has(tokens["refresh_token"])
            case .accessToken:
                let tokens = object["tokens"] as? [String: Any] ?? [:]
                return ["access_token", "accessToken"].contains { has(object[$0]) || has(tokens[$0]) }
            }
        }
    }

    /// A credential file, relative to the home folder unless an environment variable moves it.
    public struct LocalFile: Sendable {
        let variable: String?
        let variableIsDirectory: Bool
        let path: String

        /// `$variable/<name>` when set, else `~/<directory>/<name>`.
        public static func inDirectory(_ variable: String?, default directory: String, name: String) -> LocalFile {
            LocalFile(variable: variable, variableIsDirectory: true, path: "\(directory)/\(name)")
        }

        /// `$variable` when set, else `~/<path>`.
        public static func file(_ variable: String?, default path: String) -> LocalFile {
            LocalFile(variable: variable, variableIsDirectory: false, path: path)
        }

        func url(environment: [String: String], home: URL) -> URL {
            if let variable, let value = environment[variable], !value.isEmpty {
                let base = URL(fileURLWithPath: value)
                return variableIsDirectory ? base.appendingPathComponent((path as NSString).lastPathComponent) : base
            }
            return home.appendingPathComponent(path)
        }
    }

    public let id: String
    /// Providers this source connects. Empty when it varies or when the
    /// importer is idempotent on its own, in which case it always runs.
    public let providers: Set<String>
    /// May show a macOS permission prompt, so it only runs when the user asks.
    public let interactive: Bool
    public let kind: Kind

    public init(_ id: String, providers: Set<String> = [], interactive: Bool = false, kind: Kind) {
        self.id = id
        self.providers = providers
        self.interactive = interactive
        self.kind = kind
    }

    /// Every local-login importer OmniRoute offers.
    public static let all: [LoginSource] = [
        LoginSource("claude", providers: ["claude"], kind: .upload(
            files: [.inDirectory("CLAUDE_CONFIG_DIR", default: ".claude", name: ".credentials.json")],
            keychainService: "Claude Code-credentials",
            accepts: .claudeOAuth, path: "/api/providers/claude-auth/import", body: .sourceJSON
        )),
        LoginSource("codex", providers: ["codex"], kind: .upload(
            files: [.inDirectory("CODEX_HOME", default: ".codex", name: "auth.json")],
            accepts: .codexTokens, path: "/api/providers/codex-auth/import", body: .sourceJSON
        )),
        LoginSource("grok-cli", providers: ["grok-cli"], kind: .upload(
            files: [.file("GROK_AUTH_PATH", default: ".grok/auth.json")],
            accepts: .accessToken, path: "/api/oauth/grok-cli/import-token", body: .tokenText
        )),
        LoginSource("cursor", providers: ["cursor"], kind: .detectThenImport(
            detect: "/api/oauth/cursor/auto-import", save: "/api/oauth/cursor/import",
            fields: ["accessToken", "refreshToken", "machineId"]
        )),
        LoginSource("kiro", providers: ["kiro"], kind: .serverScan(
            method: "GET", path: "/api/oauth/kiro/auto-import", query: ["targetProvider": "kiro"]
        )),
        LoginSource("antigravity", kind: .serverScan(
            method: "POST", path: "/api/providers/agy-auth/apply-local", json: #"{"overwriteExisting":false}"#
        )),
        LoginSource("cliproxyapi", kind: .listThenImport(path: "/api/oauth/cliproxy-import")),
        // Zed keeps its keys in the Keychain, which OmniRoute's node process cannot read without a prompt.
        LoginSource("zed", interactive: true, kind: .serverScan(method: "POST", path: "/api/providers/zed/import"))
    ]
}

/// Runs login sources against OmniRoute.
public struct LoginImporter: Sendable {
    public struct Failure: Equatable, Sendable {
        public let source: String
        public let message: String
    }

    let client: OmniRouteClient
    let environment: [String: String]
    let home: URL
    let keychain: @Sendable (String) -> Data?

    public init(
        client: OmniRouteClient,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        keychain: @escaping @Sendable (String) -> Data? = { LoginImporter.keychainItem(service: $0) }
    ) {
        self.client = client
        self.environment = environment
        self.home = home
        self.keychain = keychain
    }

    /// Runs each source that could add something new. Sources that find nothing
    /// stay silent. Failures are reported only when a login was found locally
    /// but OmniRoute rejected it.
    public func run(
        _ sources: [LoginSource] = LoginSource.all,
        connected: Set<String>,
        includeInteractive: Bool
    ) async -> [Failure] {
        var failures: [Failure] = []
        for source in sources where includeInteractive || !source.interactive {
            if !source.providers.isEmpty, source.providers.isSubset(of: connected) { continue }
            if let message = await run(source, connected: connected) {
                failures.append(Failure(source: source.id, message: message))
            }
        }
        return failures
    }

    /// Returns an error message only for a found login that failed to import.
    func run(_ source: LoginSource, connected: Set<String>) async -> String? {
        switch source.kind {
        case .upload(let files, let keychainService, let shape, let path, let body):
            guard let credential = credential(files: files, keychainService: keychainService, shape: shape),
                  let json = Self.wrap(credential, as: body) else { return nil }
            return await post(path, json: json)
        case .serverScan(let method, let path, let query, let json):
            let items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            _ = try? await client.call(method, path, query: items, json: json.map { Data($0.utf8) })
            return nil
        case .detectThenImport(let detect, let save, let fields):
            return await detectThenImport(detect: detect, save: save, fields: fields)
        case .listThenImport(let path):
            await listThenImport(path: path, connected: connected)
            return nil
        }
    }

    /// Posts a found login. A duplicate or a vanished server is not the login's fault.
    private func post(_ path: String, json: Data) async -> String? {
        do {
            _ = try await client.call("POST", path, json: json)
        } catch OmniRouteError.http(409, _) {
            return nil
        } catch OmniRouteError.unreachable {
            return nil
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private func detectThenImport(detect: String, save: String, fields: [String]) async -> String? {
        guard let data = try? await client.call("GET", detect),
              let found = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              found["found"] as? Bool == true else { return nil }
        let payload = found.filter { fields.contains($0.key) && ($0.value as? String).map { !$0.isEmpty } == true }
        guard let json = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return await post(save, json: json)
    }

    private func listThenImport(path: String, connected: Set<String>) async {
        guard let data = try? await client.call("GET", path),
              let listing = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = listing["accounts"] as? [[String: Any]] else { return }
        let providers = Set(accounts.compactMap { $0["provider"] as? String })
        // The bulk importer does not deduplicate, so only run it for something new.
        guard !providers.isEmpty, !providers.isSubset(of: connected) else { return }
        _ = try? await client.call("POST", path)
    }

    func credential(files: [LoginSource.LocalFile], keychainService: String?, shape: LoginSource.Shape) -> Data? {
        for file in files {
            if let data = try? Data(contentsOf: file.url(environment: environment, home: home)), shape.accepts(data) {
                return data
            }
        }
        if let keychainService, let data = keychain(keychainService), shape.accepts(data) { return data }
        return nil
    }

    static func wrap(_ credential: Data, as body: LoginSource.Body) -> Data? {
        let payload: [String: Any]
        switch body {
        case .sourceJSON:
            guard let object = try? JSONSerialization.jsonObject(with: credential) else { return nil }
            payload = ["source": ["kind": "json", "json": object], "overwriteExisting": false]
        case .tokenText:
            guard let text = String(data: credential, encoding: .utf8) else { return nil }
            payload = ["token": text]
        }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    /// Reads a generic password through `/usr/bin/security`. Tools such as Claude
    /// Code store their login with that same binary, so the item's access list
    /// already trusts it and macOS shows no prompt, even after RouteBar updates.
    public static func keychainItem(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
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
        var trimmed = data
        while let last = trimmed.last, last == 0x0a || last == 0x0d {
            trimmed.removeLast()
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
