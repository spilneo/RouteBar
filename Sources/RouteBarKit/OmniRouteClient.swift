import Foundation

public enum OmniRouteError: LocalizedError, Equatable {
    case unauthorized
    case http(Int, String?)
    case unreachable

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "OmniRoute refused RouteBar's local token."
        case .http(let status, let message):
            message ?? "OmniRoute answered HTTP \(status)."
        case .unreachable:
            "OmniRoute is not reachable."
        }
    }
}

/// Result of handing a local login to OmniRoute.
public enum ImportOutcome: Equatable, Sendable {
    case imported
    case alreadyPresent
}

/// Minimal client for the loopback OmniRoute API.
///
/// Management routes (`/api/*`) carry the local CLI token. `/v1/*` routes are
/// the public inference surface and need no credential unless the operator
/// enabled `REQUIRE_API_KEY`.
public struct OmniRouteClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let cliToken: String?

    public init(baseURL: URL = OmniRoute.baseURL, cliToken: String? = CLIToken.current(), timeout: TimeInterval = 4) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.connectionProxyDictionary = [:] // Loopback only: never route through a system proxy.
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
        self.cliToken = cliToken
    }

    public func isOnline() async -> Bool {
        guard let (_, response) = try? await session.data(for: request("/api/health")) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    public func connections() async throws -> [Connection] {
        try await get("/api/providers", as: ConnectionsResponse.self).connections
    }

    public func catalog() async throws -> [String: CatalogProvider] {
        try await get("/api/models/catalog", as: CatalogResponse.self).catalog
    }

    /// One id per model (`?prefix=alias`) instead of the doubled `dual` catalog.
    public func models() async throws -> [ModelEntry] {
        try await get("/v1/models", query: [URLQueryItem(name: "prefix", value: "alias")], as: ModelsResponse.self).data
    }

    public func analytics(range: String) async throws -> Analytics {
        try await get("/api/usage/analytics", query: [URLQueryItem(name: "range", value: range)], as: Analytics.self)
    }

    /// Asks OmniRoute to exit, whoever started it.
    public func shutdown() async throws {
        _ = try await send(request("/api/shutdown", method: "POST", body: Data("{}".utf8)))
    }

    /// Imports a Claude Code `.credentials.json` (`{"claudeAiOauth": …}`).
    public func importClaudeLogin(_ credentials: Data) async throws -> ImportOutcome {
        try await importLogin(path: "/api/providers/claude-auth/import", json: credentials)
    }

    /// Imports a Codex CLI `auth.json`.
    public func importCodexLogin(_ auth: Data) async throws -> ImportOutcome {
        try await importLogin(path: "/api/providers/codex-auth/import", json: auth)
    }

    // MARK: - Plumbing

    private func importLogin(path: String, json: Data) async throws -> ImportOutcome {
        let object = try JSONSerialization.jsonObject(with: json)
        let payload: [String: Any] = ["source": ["kind": "json", "json": object], "overwriteExisting": false]
        let body = try JSONSerialization.data(withJSONObject: payload)
        do {
            _ = try await send(request(path, method: "POST", body: body))
            return .imported
        } catch OmniRouteError.http(409, _) {
            return .alreadyPresent
        }
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        let data = try await send(request(path, query: query))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if path.hasPrefix("/api/"), let cliToken {
            request.setValue(cliToken, forHTTPHeaderField: CLIToken.header)
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OmniRouteError.unreachable
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return data
        case 401, 403:
            throw OmniRouteError.unauthorized
        default:
            throw OmniRouteError.http(status, Self.errorMessage(in: data))
        }
    }

    static func errorMessage(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["error"] as? String { return message }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return object["message"] as? String
    }
}
