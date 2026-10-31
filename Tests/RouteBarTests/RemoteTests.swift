import Foundation
@testable import RouteBarKit
import XCTest

final class ServerAddressTests: XCTestCase {
    func testNormalizeAddsSchemeAndDefaultPortToBareHosts() {
        XCTAssertEqual(ServerAddress.normalize("192.168.1.20")?.absoluteString, "http://192.168.1.20:20128")
        XCTAssertEqual(ServerAddress.normalize(" Box.local:3000 ")?.absoluteString, "http://box.local:3000")
        XCTAssertEqual(ServerAddress.normalize("https://ai.example.com/dashboard?x=1")?.absoluteString, "https://ai.example.com")
        XCTAssertEqual(ServerAddress.normalize("http://user:pw@10.0.0.2:8080/v1")?.absoluteString, "http://10.0.0.2:8080")
    }

    func testNormalizeRejectsJunk() {
        XCTAssertNil(ServerAddress.normalize(""))
        XCTAssertNil(ServerAddress.normalize("ftp://example.com"))
        XCTAssertNil(ServerAddress.normalize("two words"))
        XCTAssertNil(ServerAddress.normalize("http://"))
    }

    func testLoopbackAndPrivateHosts() throws {
        func url(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text)) }
        XCTAssertTrue(try ServerAddress.isLoopback(url("http://127.0.0.1:20128")))
        XCTAssertTrue(try ServerAddress.isLoopback(url("http://localhost:1")))
        XCTAssertTrue(try ServerAddress.isLoopback(url("http://[::1]:1")))
        XCTAssertFalse(try ServerAddress.isLoopback(url("http://127.0.0.1.example.com")))
        XCTAssertFalse(try ServerAddress.isLoopback(url("http://192.168.1.2")))

        for host in ["10.1.2.3", "172.20.0.1", "192.168.68.53", "100.101.1.1", "nas.local", "box", "pi.tail1.ts.net"] {
            XCTAssertTrue(try ServerAddress.isPrivate(url("http://\(host)")), host)
        }
        for host in ["8.8.8.8", "172.32.0.1", "ai.example.com"] {
            XCTAssertFalse(try ServerAddress.isPrivate(url("http://\(host)")), host)
        }
    }

    func testEndpointAndLabel() throws {
        let root = try XCTUnwrap(URL(string: "http://192.168.68.53:20128"))
        XCTAssertEqual(ServerAddress.endpoint(for: root), "http://192.168.68.53:20128/v1")
        XCTAssertEqual(ServerAddress.label(for: root), "192.168.68.53:20128")
    }
}

final class NetworkAddressTests: XCTestCase {
    typealias Interface = NetworkAddress.Interface

    func testPrefersWiFiOrEthernetOverVPN() {
        let interfaces = [
            Interface(name: "utun4", address: "10.8.0.2"),
            Interface(name: "bridge100", address: "192.168.2.1"),
            Interface(name: "en1", address: "192.168.68.60"),
            Interface(name: "en0", address: "192.168.68.53")
        ]
        XCTAssertEqual(NetworkAddress.best(among: interfaces), "192.168.68.53")
    }

    func testSkipsLinkLocalAndTunnelsOnly() {
        XCTAssertNil(NetworkAddress.best(among: [
            Interface(name: "utun0", address: "10.0.0.2"),
            Interface(name: "en0", address: "169.254.10.1"),
            Interface(name: "lo0", address: "127.0.0.1")
        ]))
    }

    func testPrivateAddressBeatsPublicOnTheSameKind() {
        XCTAssertEqual(NetworkAddress.best(among: [
            Interface(name: "en0", address: "81.2.3.4"),
            Interface(name: "en5", address: "10.0.0.7")
        ]), "10.0.0.7")
    }
}

final class RemoteClientTests: XCTestCase {
    override func setUp() {
        StubProtocol.routes = [:]
        StubProtocol.requests = []
    }

    func client(_ base: String, cliToken: String? = "machine", accessToken: String? = nil) -> OmniRouteClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return OmniRouteClient(baseURL: URL(string: base)!, configuration: configuration, cliToken: cliToken, accessToken: accessToken)
    }

    func testRemoteNeverReceivesTheMachineToken() async throws {
        StubProtocol.routes = ["GET /api/providers": (200, #"{"connections":[]}"#)]
        _ = try await client("http://192.168.1.20:20128", accessToken: "oma_x").connections()
        let headers = try XCTUnwrap(StubProtocol.requests.first?.headers)
        XCTAssertNil(headers[CLIToken.header])
        XCTAssertEqual(headers["Authorization"], "Bearer oma_x")
    }

    func testLocalSendsTheMachineToken() async throws {
        StubProtocol.routes = ["GET /api/providers": (200, #"{"connections":[]}"#)]
        _ = try await client("http://127.0.0.1:20128").connections()
        XCTAssertEqual(StubProtocol.requests.first?.headers[CLIToken.header], "machine")
    }

    func testRemoteReadsModelsThroughTheManagementAPI() async throws {
        let body = #"{"data":[{"id":"cc/opus","owned_by":"claude"}]}"#
        StubProtocol.routes = ["GET /api/v1/models": (200, body), "GET /v1/models": (200, body)]
        _ = try await client("http://10.0.0.5:20128", accessToken: "oma_x").models()
        _ = try await client("http://127.0.0.1:20128").models()
        XCTAssertEqual(StubProtocol.requests.map(\.path), ["/api/v1/models", "/v1/models"])
        XCTAssertEqual(StubProtocol.requests.first?.query, "prefix=alias")
    }

    func testMintingSendsPasswordAndReturnsToken() async throws {
        StubProtocol.routes = ["POST /api/cli/connect": (200, #"{"token":"oma_new","scope":"admin"}"#)]
        let minted = try await client("http://10.0.0.5:20128", cliToken: nil).mintAccessToken(password: "pw", name: "RouteBar")
        XCTAssertEqual(minted.token, "oma_new")
        let body = try XCTUnwrap(StubProtocol.requests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["password": "pw", "name": "RouteBar", "scope": "admin"])
    }

    func testRemoteRefusalAsksToSignInAgain() async {
        StubProtocol.routes = ["GET /api/providers": (401, #"{"error":"Invalid management token"}"#)]
        do {
            _ = try await client("http://10.0.0.5:20128", accessToken: "oma_old").connections()
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? OmniRouteError, .refused("Invalid management token"))
        }
    }
}

final class AccountTests: XCTestCase {
    func testConnectionReadsOnlyTheAccountLabel() throws {
        let json = #"""
        {"connections":[
          {"id":"a","provider":"claude","name":"Claude (imported)","isActive":true,
           "providerSpecificData":{"email":"me@example.com","accessToken":"secret"}},
          {"id":"b","provider":"claude","name":"Claude (imported)","isActive":true,"providerSpecificData":"opaque"}
        ]}
        """#
        let connections = try JSONDecoder().decode(ConnectionsResponse.self, from: Data(json.utf8)).connections
        XCTAssertEqual(connections.map(\.account), ["me@example.com", nil])
    }

    func testSeveralAccountsOfOneProviderStayApart() throws {
        let connections = [
            Connection(id: "a", provider: "claude", name: "Claude (imported)", isActive: true),
            Connection(id: "b", provider: "claude", name: "Claude (imported)", isActive: true),
            Connection(id: "c", provider: "claude", name: "Work", isActive: false),
            Connection(id: "d", provider: "codex", isActive: true, account: "dev@example.com")
        ]
        let five = { (used: Double) in QuotaWindow(label: "5h", usedPercent: used, resetsAt: nil) }
        let tiles = Dashboard.tiles(connections: connections, catalog: [:], quotas: ["a": [five(10)], "b": [five(70)], "c": [five(99)]])

        XCTAssertEqual(tiles.map(\.id), ["claude", "codex"])
        let claude = try XCTUnwrap(tiles.first)
        XCTAssertEqual(claude.accounts.map(\.name), ["Claude (imported)", "Claude (imported) 2", "Work"])
        XCTAssertEqual(claude.activeAccounts, 2)
        XCTAssertEqual(claude.accounts.map { $0.quotas.first?.usedPercent }, [10, 70, nil], "inactive accounts show no limits")
        XCTAssertEqual(claude.quotas.first?.usedPercent, 70, "the tile shows the busiest usable account")
        XCTAssertEqual(tiles.last?.accounts.map(\.name), ["dev@example.com"])
    }
}
