import Foundation
@testable import RouteBarKit
import XCTest

/// Answers requests from a table and records them, so importer runs can be checked offline.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    struct Recorded {
        let method: String
        let path: String
        let body: Data?
    }

    nonisolated(unsafe) static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) static var requests: [Recorded] = []

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        Self.requests.append(Recorded(method: method, path: path, body: request.httpBody ?? request.httpBodyStream.map(Self.read)))
        let (status, body) = Self.routes["\(method) \(path)"] ?? (404, #"{"error":"not found"}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class LoginImporterTests: XCTestCase {
    var home: URL!

    override func setUp() {
        StubProtocol.routes = [:]
        StubProtocol.requests = []
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    func importer(keychain: @escaping @Sendable (String) -> Data? = { _ in nil }) -> LoginImporter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = OmniRouteClient(baseURL: URL(string: "http://127.0.0.1:1")!, configuration: configuration, cliToken: "t")
        return LoginImporter(client: client, environment: [:], home: home, keychain: keychain)
    }

    func write(_ text: String, to path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func paths() -> [String] { StubProtocol.requests.map { "\($0.method) \($0.path)" } }

    func testShapes() {
        XCTAssertTrue(LoginSource.Shape.claudeOAuth.accepts(Data(#"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r"}}"#.utf8)))
        XCTAssertFalse(LoginSource.Shape.claudeOAuth.accepts(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
        XCTAssertTrue(LoginSource.Shape.codexTokens.accepts(Data(#"{"tokens":{"id_token":"i","access_token":"a","refresh_token":"r"}}"#.utf8)))
        XCTAssertFalse(LoginSource.Shape.codexTokens.accepts(Data(#"{"OPENAI_API_KEY":"sk"}"#.utf8)), "API-key mode is not a login")
        XCTAssertTrue(LoginSource.Shape.accessToken.accepts(Data(#"{"access_token":"eyJ"}"#.utf8)))
        XCTAssertFalse(LoginSource.Shape.accessToken.accepts(Data("not json".utf8)))
    }

    func testEnvironmentMovesFiles() {
        let directory = LoginSource.LocalFile.inDirectory("CODEX_HOME", default: ".codex", name: "auth.json")
        XCTAssertEqual(directory.url(environment: ["CODEX_HOME": "/x"], home: home).path, "/x/auth.json")
        XCTAssertEqual(directory.url(environment: [:], home: home).path, home.appendingPathComponent(".codex/auth.json").path)
        let file = LoginSource.LocalFile.file("GROK_AUTH_PATH", default: ".grok/auth.json")
        XCTAssertEqual(file.url(environment: ["GROK_AUTH_PATH": "/y/z.json"], home: home).path, "/y/z.json")
    }

    func testUploadsFoundLoginsAndSkipsConnectedProviders() async throws {
        try write(#"{"tokens":{"id_token":"i","access_token":"a","refresh_token":"r"}}"#, to: ".codex/auth.json")
        try write(#"{"access_token":"eyJ.a.b"}"#, to: ".grok/auth.json")
        StubProtocol.routes["POST /api/providers/codex-auth/import"] = (200, "{}")
        StubProtocol.routes["POST /api/oauth/grok-cli/import-token"] = (200, "{}")
        let claude = Data(#"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r"}}"#.utf8)

        let failures = await importer(keychain: { _ in claude }).run(
            [LoginSource.all[0], LoginSource.all[1], LoginSource.all[2]], connected: ["claude"], includeInteractive: false
        )

        XCTAssertEqual(failures, [])
        XCTAssertEqual(paths(), ["POST /api/providers/codex-auth/import", "POST /api/oauth/grok-cli/import-token"],
                       "claude is already connected, so its Keychain item is not even read into a request")
        let codexBody = try JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.requests[0].body)) as? [String: Any]
        XCTAssertEqual(codexBody?["overwriteExisting"] as? Bool, false)
        XCTAssertEqual((codexBody?["source"] as? [String: Any])?["kind"] as? String, "json")
        let grokBody = try JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.requests[1].body)) as? [String: Any]
        XCTAssertEqual(grokBody?["token"] as? String, #"{"access_token":"eyJ.a.b"}"#)
    }

    func testRejectedUploadIsReportedButDuplicateIsNot() async throws {
        try write(#"{"tokens":{"id_token":"i","access_token":"a","refresh_token":"r"}}"#, to: ".codex/auth.json")
        StubProtocol.routes["POST /api/providers/codex-auth/import"] = (400, #"{"error":"id_token is invalid"}"#)
        let failures = await importer().run([LoginSource.all[1]], connected: [], includeInteractive: false)
        XCTAssertEqual(failures, [LoginImporter.Failure(source: "codex", message: "id_token is invalid")])

        StubProtocol.routes["POST /api/providers/codex-auth/import"] = (409, #"{"error":"duplicate"}"#)
        let again = await importer().run([LoginSource.all[1]], connected: [], includeInteractive: false)
        XCTAssertEqual(again, [])
    }

    func testDetectThenImportForwardsOnlyListedFields() async throws {
        StubProtocol.routes["GET /api/oauth/cursor/auto-import"] =
            (200, #"{"found":true,"accessToken":"a","machineId":"m","refreshToken":"","source":"ide"}"#)
        StubProtocol.routes["POST /api/oauth/cursor/import"] = (200, "{}")
        let cursor = try XCTUnwrap(LoginSource.all.first { $0.id == "cursor" })
        _ = await importer().run([cursor], connected: [], includeInteractive: false)
        XCTAssertEqual(paths(), ["GET /api/oauth/cursor/auto-import", "POST /api/oauth/cursor/import"])
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(StubProtocol.requests[1].body)) as? [String: String]
        XCTAssertEqual(body, ["accessToken": "a", "machineId": "m"])
    }

    func testBulkImportRunsOnlyForSomethingNew() async throws {
        let cliproxy = try XCTUnwrap(LoginSource.all.first { $0.id == "cliproxyapi" })
        StubProtocol.routes["GET /api/oauth/cliproxy-import"] = (200, #"{"accounts":[{"provider":"claude"}]}"#)
        StubProtocol.routes["POST /api/oauth/cliproxy-import"] = (200, #"{"imported":1}"#)

        _ = await importer().run([cliproxy], connected: ["claude"], includeInteractive: false)
        XCTAssertEqual(paths(), ["GET /api/oauth/cliproxy-import"])

        StubProtocol.requests = []
        _ = await importer().run([cliproxy], connected: [], includeInteractive: false)
        XCTAssertEqual(paths(), ["GET /api/oauth/cliproxy-import", "POST /api/oauth/cliproxy-import"])
    }

    func testPromptingSourcesRunOnlyOnRequest() async throws {
        let zed = try XCTUnwrap(LoginSource.all.first { $0.id == "zed" })
        _ = await importer().run([zed], connected: [], includeInteractive: false)
        XCTAssertEqual(paths(), [])
        _ = await importer().run([zed], connected: [], includeInteractive: true)
        XCTAssertEqual(paths(), ["POST /api/providers/zed/import"])
    }
}
