import Foundation

/// One provider connection from `GET /api/providers`. Credentials are never decoded:
/// from `providerSpecificData` only the account's email or display name is read.
public struct Connection: Decodable, Sendable, Equatable {
    public let id: String?
    public let provider: String
    public let name: String?
    public let isActive: Bool?
    public let testStatus: String?
    /// The account behind the connection, such as an email, when OmniRoute knows it.
    public let account: String?

    public init(
        id: String? = nil,
        provider: String,
        name: String? = nil,
        isActive: Bool? = nil,
        testStatus: String? = nil,
        account: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.isActive = isActive
        self.testStatus = testStatus
        self.account = account
    }

    enum CodingKeys: String, CodingKey {
        case id, provider, name, isActive, testStatus, email, displayName, providerSpecificData
    }

    enum AccountKeys: String, CodingKey {
        case email, accountEmail, displayName, login, username
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        provider = (try? container.decodeIfPresent(String.self, forKey: .provider)) ?? ""
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        isActive = try? container.decodeIfPresent(Bool.self, forKey: .isActive)
        testStatus = try? container.decodeIfPresent(String.self, forKey: .testStatus)
        let nested = try? container.nestedContainer(keyedBy: AccountKeys.self, forKey: .providerSpecificData)
        let candidates: [String?] = [
            try? container.decodeIfPresent(String.self, forKey: .email),
            nested.flatMap { try? $0.decodeIfPresent(String.self, forKey: .email) },
            nested.flatMap { try? $0.decodeIfPresent(String.self, forKey: .accountEmail) },
            try? container.decodeIfPresent(String.self, forKey: .displayName),
            nested.flatMap { try? $0.decodeIfPresent(String.self, forKey: .displayName) },
            nested.flatMap { try? $0.decodeIfPresent(String.self, forKey: .login) },
            nested.flatMap { try? $0.decodeIfPresent(String.self, forKey: .username) }
        ]
        account = candidates.lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    /// Enabled and not known to be broken.
    public var isUsable: Bool {
        guard isActive ?? false else { return false }
        let broken: Set = ["error", "expired", "unauthorized", "banned", "disabled", "invalid"]
        return !broken.contains(testStatus?.lowercased() ?? "")
    }
}

struct ConnectionsResponse: Decodable {
    let connections: [Connection]
}

/// One entry of the OpenAI-style `GET /v1/models` list.
public struct ModelEntry: Decodable, Sendable, Equatable {
    public let id: String
    public let ownedBy: String?

    public init(id: String, ownedBy: String?) {
        self.id = id
        self.ownedBy = ownedBy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

struct ModelsResponse: Decodable {
    let data: [ModelEntry]
}

/// `GET /api/models/catalog`: display names and model ids keyed by provider id.
public struct CatalogProvider: Decodable, Sendable, Equatable {
    public struct Model: Decodable, Sendable, Equatable {
        public let id: String
    }

    public let provider: String?
    public let models: [Model]?

    public init(provider: String?, modelIDs: [String]) {
        self.provider = provider
        self.models = modelIDs.map(Model.init(id:))
    }
}

struct CatalogResponse: Decodable {
    let catalog: [String: CatalogProvider]
}

/// The parts of `GET /api/usage/analytics` that RouteBar charts.
public struct Analytics: Decodable, Sendable, Equatable {
    public struct Summary: Decodable, Sendable, Equatable {
        public var totalRequests: Int?
        public var totalTokens: Int?
        public var successRatePct: Double?
        public var avgLatencyMs: Double?

        public init(totalRequests: Int? = nil, totalTokens: Int? = nil, successRatePct: Double? = nil, avgLatencyMs: Double? = nil) {
            self.totalRequests = totalRequests
            self.totalTokens = totalTokens
            self.successRatePct = successRatePct
            self.avgLatencyMs = avgLatencyMs
        }

        enum CodingKeys: String, CodingKey {
            case totalRequests, totalTokens, successRatePct, avgLatencyMs
        }

        // OmniRoute reports some rates as strings ("100.00"), so every field is read leniently.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func number(_ key: CodingKeys) -> Double? {
                if let value = try? container.decode(Double.self, forKey: key) { return value }
                return (try? container.decode(String.self, forKey: key)).flatMap(Double.init)
            }
            totalRequests = number(.totalRequests).map { Int($0) }
            totalTokens = number(.totalTokens).map { Int($0) }
            successRatePct = number(.successRatePct)
            avgLatencyMs = number(.avgLatencyMs)
        }
    }

    public struct Day: Decodable, Sendable, Equatable {
        public var date: String
        public var requests: Int?
        public var totalTokens: Int?

        public init(date: String, requests: Int?, totalTokens: Int?) {
            self.date = date
            self.requests = requests
            self.totalTokens = totalTokens
        }
    }

    public var summary: Summary?
    public var dailyTrend: [Day]?

    public init(summary: Summary? = nil, dailyTrend: [Day]?) {
        self.summary = summary
        self.dailyTrend = dailyTrend
    }
}

/// `GET /api/system/version`
public struct ServerVersion: Decodable, Sendable, Equatable {
    public let current: String?
    public let latest: String?
    public let updateAvailable: Bool?

    public init(current: String?, latest: String?, updateAvailable: Bool?) {
        self.current = current
        self.latest = latest
        self.updateAvailable = updateAvailable
    }
}

/// `GET /api/cli/whoami`
public struct WhoAmI: Decodable, Sendable, Equatable {
    public let authenticated: Bool?
    public let viaAccessToken: Bool?
    public let name: String?
    public let scope: String?
    public let expiresAt: String?
}

/// `POST /api/cli/connect`: the plaintext token is only ever returned here.
public struct MintedToken: Decodable, Sendable {
    public let token: String
    public let scope: String?
    public let expiresAt: String?
}

/// `GET|POST /api/tunnels/cloudflared`: OmniRoute's Cloudflare quick tunnel,
/// which gives the local server a public `https://….trycloudflare.com` address.
public struct TunnelStatus: Decodable, Sendable, Equatable {
    public enum Phase: String, Decodable, Sendable {
        case unsupported
        case notInstalled = "not_installed"
        case stopped
        case starting
        case running
        case error
        case unknown

        public init(from decoder: Decoder) throws {
            self = try Phase(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let running: Bool
    public let phase: Phase
    public let publicUrl: String?
    public let lastError: String?

    public init(running: Bool, phase: Phase, publicUrl: String? = nil, lastError: String? = nil) {
        self.running = running
        self.phase = phase
        self.publicUrl = publicUrl
        self.lastError = lastError
    }

    enum CodingKeys: String, CodingKey {
        case running, phase, publicUrl, lastError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        running = try container.decodeIfPresent(Bool.self, forKey: .running) ?? false
        phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .unknown
        publicUrl = try container.decodeIfPresent(String.self, forKey: .publicUrl)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }

    /// The public server root, only while the tunnel is up and only for an https address.
    public var publicRoot: URL? {
        guard running, let publicUrl, let url = URL(string: publicUrl), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}

/// `POST /api/tunnels/cloudflared` answers with the new status wrapped in `status`.
struct TunnelActionResponse: Decodable {
    let status: TunnelStatus?
}

/// `GET /api/settings/feature-flags`, reduced to what RouteBar reads.
struct FeatureFlagsResponse: Decodable {
    struct Flag: Decodable {
        let key: String
        let effectiveValue: String?
    }

    let flags: [Flag]
}

/// One client API key from `GET /api/keys`. OmniRoute masks `key` in the list;
/// the full value is only returned when a key is created or revealed.
public struct APIKeyInfo: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String?
    /// The masked key, for example `sk-a****wxyz`.
    public let key: String?
    public let isActive: Bool?
    public let isBanned: Bool?
    public let revokedAt: String?
    public let expiresAt: String?

    public init(id: String, name: String?, key: String?, isActive: Bool? = true, isBanned: Bool? = false,
                revokedAt: String? = nil, expiresAt: String? = nil) {
        self.id = id
        self.name = name
        self.key = key
        self.isActive = isActive
        self.isBanned = isBanned
        self.revokedAt = revokedAt
        self.expiresAt = expiresAt
    }

    /// Not revoked, banned, switched off or past its expiry.
    public func isUsable(at now: Date = Date()) -> Bool {
        guard isActive != false, isBanned != true, revokedAt == nil else { return false }
        guard let expiresAt else { return true }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: expiresAt) ?? ISO8601DateFormatter().date(from: expiresAt)
        return date.map { $0 > now } ?? true
    }
}

/// `GET /api/keys`: the keys plus whether OmniRoute lets stored keys be revealed.
public struct APIKeyList: Decodable, Sendable, Equatable {
    public let keys: [APIKeyInfo]
    public let allowKeyReveal: Bool

    public init(keys: [APIKeyInfo], allowKeyReveal: Bool) {
        self.keys = keys
        self.allowKeyReveal = allowKeyReveal
    }

    enum CodingKeys: String, CodingKey { case keys, allowKeyReveal }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decodeIfPresent([APIKeyInfo].self, forKey: .keys) ?? []
        allowKeyReveal = try container.decodeIfPresent(Bool.self, forKey: .allowKeyReveal) ?? false
    }
}

/// `POST /api/keys`: the only answer that carries a new key in full.
public struct CreatedAPIKey: Decodable, Sendable {
    public let id: String
    public let name: String?
    public let key: String
}

struct RevealedAPIKey: Decodable {
    let key: String
}
