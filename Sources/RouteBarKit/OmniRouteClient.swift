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
        self.init(baseURL: baseURL, configuration: configuration, cliToken: cliToken)
    }

    init(baseURL: URL, configuration: URLSessionConfiguration, cliToken: String?) {
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

    /// A raw management call for routes without a typed wrapper, such as the
    /// login importers. Non-2xx answers throw `OmniRouteError`.
    public func call(_ method: String, _ path: String, query: [URLQueryItem] = [], json: Data? = nil) async throws -> Data {
        try await send(request(path, method: method, query: query, body: json))
    }

    // MARK: - Plumbing

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
