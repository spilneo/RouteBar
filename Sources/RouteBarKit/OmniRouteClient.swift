import Foundation

public enum OmniRouteError: LocalizedError, Equatable {
    case unauthorized
    /// OmniRoute's `REQUIRE_API_KEY` is on and the request carried no valid client API key.
    case apiKeyRequired
    /// OmniRoute keeps stored keys hidden (`ALLOW_API_KEY_REVEAL` is off).
    case revealDisabled
    /// A remote server refused the access token, or the password for a new one.
    case refused(String?)
    case http(Int, String?)
    case unreachable

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "OmniRoute refused RouteBar's local token."
        case .apiKeyRequired:
            "OmniRoute requires an API key. Create one in Settings, Endpoint."
        case .revealDisabled:
            "OmniRoute hides stored keys. Turn on API Key Reveal in its dashboard, or create a new key in RouteBar."
        case .refused(let message):
            message ?? "The server refused RouteBar's access token. Sign in again in Settings."
        case .http(let status, let message):
            message ?? "OmniRoute answered HTTP \(status)."
        case .unreachable:
            "OmniRoute is not reachable."
        }
    }
}

/// Minimal client for an OmniRoute server, local or remote.
///
/// Management routes (`/api/*`) carry a credential: the machine-bound CLI token
/// for a loopback server, or a scoped `oma_` access token (`Authorization: Bearer`)
/// for a remote one, exactly like `omniroute connect`. The CLI token is never sent
/// to a non-loopback host. `/v1/*` is the public inference surface and needs no
/// credential on loopback, so a remote client reads models from `/api/v1/models`.
public struct OmniRouteClient: Sendable {
    public let baseURL: URL
    let session: URLSession
    let cliToken: String?
    let accessToken: String?

    public init(
        baseURL: URL = OmniRoute.baseURL,
        cliToken: String? = CLIToken.current(),
        accessToken: String? = nil,
        timeout: TimeInterval = 4
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if ServerAddress.isLoopback(baseURL) {
            configuration.connectionProxyDictionary = [:] // Loopback: never route through a system proxy.
        }
        self.init(baseURL: baseURL, configuration: configuration, cliToken: cliToken, accessToken: accessToken)
    }

    init(baseURL: URL, configuration: URLSessionConfiguration, cliToken: String?, accessToken: String? = nil) {
        self.baseURL = baseURL
        self.session = URLSession(configuration: configuration)
        self.cliToken = ServerAddress.isLoopback(baseURL) ? cliToken : nil
        self.accessToken = accessToken
    }

    /// True when the server runs on this Mac.
    public var isLocal: Bool { ServerAddress.isLoopback(baseURL) }

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
    /// `/api/v1/models` is a client API route: when OmniRoute requires an API key
    /// it refuses RouteBar's management credential and needs `apiKey`, which
    /// surfaces as `OmniRouteError.apiKeyRequired`. A local server too old to have
    /// that route falls back to the public `/v1/models`.
    public func models(apiKey: String? = nil) async throws -> [ModelEntry] {
        let query = [URLQueryItem(name: "prefix", value: "alias")]
        do {
            return try await decode(ModelsResponse.self, send(request("/api/v1/models", query: query, bearer: apiKey))).data
        } catch OmniRouteError.http(404, _) where isLocal {
            return try await decode(ModelsResponse.self, send(request("/v1/models", query: query, bearer: apiKey))).data
        } catch OmniRouteError.unauthorized where isLocal {
            throw OmniRouteError.apiKeyRequired
        }
    }

    // MARK: Client API keys

    /// The server's API keys, masked, and whether stored keys may be revealed.
    public func apiKeys() async throws -> APIKeyList {
        try await get("/api/keys", as: APIKeyList.self)
    }

    /// Creates a client API key that may use every model. The full key is only in this answer.
    public func createAPIKey(name: String) async throws -> CreatedAPIKey {
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "scopes": [String]()])
        return try await decode(CreatedAPIKey.self, send(request("/api/keys", method: "POST", body: body)))
    }

    /// A stored key in full. Throws `revealDisabled` unless `ALLOW_API_KEY_REVEAL` is on.
    public func revealAPIKey(id: String) async throws -> String {
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw OmniRouteError.http(404, nil) }
        do {
            return try await decode(RevealedAPIKey.self, send(request("/api/keys/\(escaped)/reveal"))).key
        } catch OmniRouteError.unauthorized {
            // Management calls with the local token otherwise succeed, so a refusal here is the reveal switch.
            throw OmniRouteError.revealDisabled
        } catch OmniRouteError.refused(let message) where message?.localizedCaseInsensitiveContains("reveal") == true {
            throw OmniRouteError.revealDisabled
        }
    }

    /// Asks OmniRoute to fetch a connection's model list from the provider again
    /// and keep it, which picks up models released since the connection was added.
    /// The same call as "Import from /models" in the dashboard. Returns how many models it found.
    @discardableResult
    public func refreshModels(connectionID: String) async throws -> Int {
        guard let id = connectionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return 0 }
        let data = try await send(request("/api/providers/\(id)/models", query: [URLQueryItem(name: "refresh", value: "true")]))
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["models"] as? [Any])?.count ?? 0
    }

    public func analytics(range: String) async throws -> Analytics {
        try await get("/api/usage/analytics", query: [URLQueryItem(name: "range", value: range)], as: Analytics.self)
    }

    /// Subscription limit windows for one connection. OmniRoute asks the
    /// provider for these, so callers should poll them sparingly.
    public func quotas(connectionID: String) async throws -> [QuotaWindow] {
        guard let id = connectionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        return try await Quotas.parse(send(request("/api/usage/\(id)")))
    }

    public func version() async throws -> ServerVersion {
        try await get("/api/system/version", as: ServerVersion.self)
    }

    /// Requests OmniRoute is serving right now.
    public func activeRequests() async throws -> Int {
        let data = try await send(request("/api/usage/history"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        switch object?["activeRequests"] {
        case let list as [Any]: return list.count
        case let count as NSNumber: return count.intValue
        default: return 0
        }
    }

    /// Asks OmniRoute to exit, whoever started it.
    public func shutdown() async throws {
        _ = try await send(request("/api/shutdown", method: "POST", body: Data("{}".utf8)))
    }

    // MARK: Public tunnel

    /// The Cloudflare quick tunnel's state. The route is loopback-only, so this
    /// only works for a server on this Mac.
    public func tunnelStatus() async throws -> TunnelStatus {
        try await get("/api/tunnels/cloudflared", as: TunnelStatus.self)
    }

    /// Opens or closes the quick tunnel. Opening waits until Cloudflare hands out
    /// the address (OmniRoute allows 30 seconds, more when it first downloads
    /// `cloudflared`), so this call gets a long timeout of its own.
    @discardableResult
    public func setTunnel(enabled: Bool) async throws -> TunnelStatus? {
        let body = try JSONSerialization.data(withJSONObject: ["action": enabled ? "enable" : "disable"])
        var request = request("/api/tunnels/cloudflared", method: "POST", body: body)
        request.timeoutInterval = 120
        return try await JSONDecoder().decode(TunnelActionResponse.self, from: send(request)).status
    }

    /// Whether OmniRoute's `REQUIRE_API_KEY` flag is on. When it is off, anyone who
    /// can reach the server, including through a tunnel, can use it without a key.
    public func requiresAPIKey() async throws -> Bool {
        let flags = try await get("/api/settings/feature-flags", as: FeatureFlagsResponse.self).flags
        let value = flags.first { $0.key == Self.requireAPIKeyFlag }?.effectiveValue?.lowercased()
        return ["true", "1", "yes"].contains(value ?? "")
    }

    /// Turns `REQUIRE_API_KEY` on or off. It applies to every client, including apps on this Mac.
    public func setRequiresAPIKey(_ enabled: Bool) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["key": Self.requireAPIKeyFlag, "value": enabled ? "true" : "false"])
        _ = try await send(request("/api/settings/feature-flags", method: "PUT", body: body))
    }

    static let requireAPIKeyFlag = "REQUIRE_API_KEY"

    /// The credential the server sees: for an access token its name and scope.
    public func whoami() async throws -> WhoAmI {
        try await get("/api/cli/whoami", as: WhoAmI.self)
    }

    /// Exchanges a remote server's management password for a scoped access
    /// token, the same call `omniroute connect` makes. The token is returned once.
    public func mintAccessToken(password: String, name: String, scope: String = "admin") async throws -> MintedToken {
        let body = try JSONSerialization.data(withJSONObject: ["password": password, "name": name, "scope": scope])
        let data = try await send(request("/api/cli/connect", method: "POST", body: body))
        return try JSONDecoder().decode(MintedToken.self, from: data)
    }

    /// A raw management call for routes without a typed wrapper, such as the
    /// login importers. Non-2xx answers throw `OmniRouteError`.
    public func call(_ method: String, _ path: String, query: [URLQueryItem] = [], json: Data? = nil) async throws -> Data {
        try await send(request(path, method: method, query: query, body: json))
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        try await decode(T.self, send(request(path, query: query)))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    /// `bearer` is a client API key for `/v1`-style routes, sent as `Authorization: Bearer`.
    private func request(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil, bearer: String? = nil
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if path.hasPrefix("/api/") {
            if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
            if let cliToken { request.setValue(cliToken, forHTTPHeaderField: CLIToken.header) }
        }
        if let bearer, accessToken == nil { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
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
            throw cliToken == nil ? OmniRouteError.refused(Self.errorMessage(in: data)) : OmniRouteError.unauthorized
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
