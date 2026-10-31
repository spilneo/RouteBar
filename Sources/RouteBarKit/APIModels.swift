import Foundation

/// One provider connection from `GET /api/providers`. Credentials are never decoded.
public struct Connection: Decodable, Sendable, Equatable {
    public let id: String?
    public let provider: String
    public let name: String?
    public let isActive: Bool?
    public let testStatus: String?

    public init(id: String? = nil, provider: String, name: String? = nil, isActive: Bool? = nil, testStatus: String? = nil) {
        self.id = id
        self.provider = provider
        self.name = name
        self.isActive = isActive
        self.testStatus = testStatus
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
