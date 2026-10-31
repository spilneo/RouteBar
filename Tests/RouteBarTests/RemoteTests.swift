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

    func testLiveInterfacesAreDottedIPv4() {
        for interface in NetworkAddress.interfaces() {
            let octets = interface.address.split(separator: ".")
            XCTAssertEqual(octets.count, 4, interface.address)
            XCTAssertTrue(octets.allSatisfy { UInt8($0) != nil }, interface.address)
            XCTAssertFalse(interface.name.isEmpty)
        }
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

    func testModelsAreReadThroughTheManagementAPI() async throws {
        let body = #"{"data":[{"id":"cc/opus","owned_by":"claude"}]}"#
        StubProtocol.routes = ["GET /api/v1/models": (200, body), "GET /v1/models": (200, body)]
        _ = try await client("http://10.0.0.5:20128", accessToken: "oma_x").models()
        _ = try await client("http://127.0.0.1:20128").models()
        XCTAssertEqual(StubProtocol.requests.map(\.path), ["/api/v1/models", "/api/v1/models"])
        XCTAssertEqual(StubProtocol.requests.first?.query, "prefix=alias")
        XCTAssertEqual(StubProtocol.requests.last?.headers[CLIToken.header], "machine", "works when /v1 requires an API key")
    }

    func testOlderLocalServerFallsBackToPublicModels() async throws {
        StubProtocol.routes = ["GET /v1/models": (200, #"{"data":[{"id":"cc/opus","owned_by":"claude"}]}"#)]
        let models = try await client("http://127.0.0.1:20128").models()
        XCTAssertEqual(models.map(\.id), ["cc/opus"])
        XCTAssertEqual(StubProtocol.requests.map(\.path), ["/api/v1/models", "/v1/models"])
    }

    func testTunnelEnableSendsActionAndReadsPublicAddress() async throws {
        StubProtocol.routes = ["POST /api/tunnels/cloudflared": (200, #"""
        {"success":true,"action":"enable","status":{"supported":true,"installed":true,"running":true,"pid":1,
         "publicUrl":"https://abc-def.trycloudflare.com","apiUrl":"https://abc-def.trycloudflare.com/v1",
         "targetUrl":"http://127.0.0.1:20128","phase":"running","lastError":null}}
        """#)]
        let status = try await client("http://127.0.0.1:20128").setTunnel(enabled: true)
        XCTAssertEqual(status?.phase, .running)
        XCTAssertEqual(status?.publicRoot?.absoluteString, "https://abc-def.trycloudflare.com")
        let body = try XCTUnwrap(StubProtocol.requests.first?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["action": "enable"])
        XCTAssertEqual(StubProtocol.requests.first?.headers[CLIToken.header], "machine")
    }

    func testTunnelStatusToleratesUnknownPhasesAndHidesStoppedAddresses() throws {
        let decode = { (json: String) in try JSONDecoder().decode(TunnelStatus.self, from: Data(json.utf8)) }
        let stopped = try decode(#"{"running":false,"phase":"stopped","publicUrl":"https://old.trycloudflare.com"}"#)
        XCTAssertNil(stopped.publicRoot, "a stopped tunnel's last address no longer works")
        XCTAssertEqual(try decode(#"{"running":false,"phase":"rebooting"}"#).phase, .unknown)
        XCTAssertEqual(try decode(#"{"phase":"not_installed"}"#).phase, .notInstalled)
        XCTAssertNil(try decode(#"{"running":true,"phase":"running","publicUrl":"http://plain.example"}"#).publicRoot)
    }

    func testRequireAPIKeyFlag() async throws {
        StubProtocol.routes = [
            "GET /api/settings/feature-flags": (
                200, #"{"flags":[{"key":"OTHER","effectiveValue":"true"},{"key":"REQUIRE_API_KEY","effectiveValue":"false"}]}"#
            ),
            "PUT /api/settings/feature-flags": (200, "{}")
        ]
        let local = client("http://127.0.0.1:20128")
        let required = try await local.requiresAPIKey()
        XCTAssertFalse(required)
        try await local.setRequiresAPIKey(true)
        let body = try XCTUnwrap(StubProtocol.requests.last?.body)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["key": "REQUIRE_API_KEY", "value": "true"])
    }

    func testRequiredKeyIsReportedInsteadOfARefusedLocalToken() async throws {
        StubProtocol.routes = ["GET /api/v1/models": (401, #"{"error":{"code":"AUTH_002","message":"Authentication required"}}"#)]
        do {
            _ = try await client("http://127.0.0.1:20128").models()
            XCTFail("expected apiKeyRequired")
        } catch {
            XCTAssertEqual(error as? OmniRouteError, .apiKeyRequired)
        }
    }

    func testModelsWithAnAPIKeySendBothCredentials() async throws {
        StubProtocol.routes = ["GET /api/v1/models": (200, #"{"data":[]}"#)]
        _ = try await client("http://127.0.0.1:20128").models(apiKey: "sk-test")
        let headers = try XCTUnwrap(StubProtocol.requests.first?.headers)
        XCTAssertEqual(headers["Authorization"], "Bearer sk-test")
        XCTAssertEqual(headers[CLIToken.header], "machine")
    }

    func testRemoteAccessTokenIsNotReplacedByAnAPIKey() async throws {
        StubProtocol.routes = ["GET /api/v1/models": (200, #"{"data":[]}"#)]
        _ = try await client("http://10.0.0.5:20128", accessToken: "oma_x").models(apiKey: "sk-test")
        XCTAssertEqual(StubProtocol.requests.first?.headers["Authorization"], "Bearer oma_x")
    }

    func testCreatingAKeyReturnsItInFull() async throws {
        StubProtocol.routes = ["POST /api/keys": (200, #"{"id":"k1","name":"RouteBar","key":"sk-full-key","scopes":[]}"#)]
        let created = try await client("http://127.0.0.1:20128").createAPIKey(name: "RouteBar")
        XCTAssertEqual(created.id, "k1")
        XCTAssertEqual(created.key, "sk-full-key")
        let body = try XCTUnwrap(StubProtocol.requests.first?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "RouteBar")
        XCTAssertEqual(json["scopes"] as? [String], [])
    }

    func testRevealWorksOnlyWhenOmniRouteAllowsIt() async throws {
        let local = client("http://127.0.0.1:20128")
        StubProtocol.routes = ["GET /api/keys/k1/reveal": (200, #"{"key":"sk-full-key"}"#)]
        let revealed = try await local.revealAPIKey(id: "k1")
        XCTAssertEqual(revealed, "sk-full-key")

        StubProtocol.routes = ["GET /api/keys/k1/reveal": (403, #"{"error":"API key reveal is disabled"}"#)]
        do {
            _ = try await local.revealAPIKey(id: "k1")
            XCTFail("expected revealDisabled")
        } catch {
            XCTAssertEqual(error as? OmniRouteError, .revealDisabled)
        }
    }

    func testKeyListSkipsUnusableKeys() throws {
        let json = #"""
        {"keys":[
          {"id":"a","name":"Live","key":"sk-a****wxyz","isActive":true,"revokedAt":null,"expiresAt":null},
          {"id":"b","name":"Revoked","key":"sk-b****","isActive":true,"revokedAt":"2026-01-01T00:00:00.000Z"},
          {"id":"c","name":"Off","key":"sk-c****","isActive":false},
          {"id":"d","name":"Expired","key":"sk-d****","expiresAt":"2020-01-01T00:00:00.000Z"},
          {"id":"e","name":"Later","key":"sk-e****","expiresAt":"2999-01-01T00:00:00Z"}
        ],"allowKeyReveal":false}
        """#
        let list = try JSONDecoder().decode(APIKeyList.self, from: Data(json.utf8))
        XCTAssertFalse(list.allowKeyReveal)
        XCTAssertEqual(list.keys.filter { $0.isUsable() }.map(\.id), ["a", "e"])
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
