import Foundation
@testable import RouteBarKit
import XCTest

final class CLITokenTests: XCTestCase {
    func testDerivationMatchesHMACSHA256() {
        // printf 'salt-value' | openssl dgst -sha256 -hmac 'machine-id'
        XCTAssertEqual(
            CLIToken.derive(machineID: "machine-id", salt: "salt-value"),
            "5f2ee3fe079bbc8e87d287f53d588a830413a1d7f6856c25b1508da4dbe69e7f"
        )
    }

    func testSaltIsCreatedOnceWithOwnerOnlyPermissions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try XCTUnwrap(CLIToken.establishSalt(in: dir))
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(CLIToken.establishSalt(in: dir), first, "an existing salt must be reused")

        let file = dir.appendingPathComponent(CLIToken.saltFileName)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testMalformedSaltIsRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"salt":"short"}"#.utf8).write(to: file)
        XCTAssertNil(CLIToken.readSalt(at: file))
    }

    func testExplicitTokenWins() {
        XCTAssertEqual(CLIToken.current(environment: ["OMNIROUTE_CLI_TOKEN": "abc"]), "abc")
    }
}

final class DataDirectoryTests: XCTestCase {
    func testResolutionOrder() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        XCTAssertEqual(OmniRoute.dataDirectory(environment: ["DATA_DIR": "/custom"], home: home).path, "/custom")
        XCTAssertEqual(OmniRoute.dataDirectory(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).path, "/xdg/omniroute")
        XCTAssertEqual(OmniRoute.dataDirectory(environment: [:], home: home).lastPathComponent, ".omniroute")

        try FileManager.default.createDirectory(at: home.appendingPathComponent(".omniroute"), withIntermediateDirectories: true)
        XCTAssertEqual(OmniRoute.dataDirectory(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home).lastPathComponent, ".omniroute")
    }
}

final class DashboardTests: XCTestCase {
    let catalog: [String: CatalogProvider] = [
        "claude": CatalogProvider(provider: "Claude Code", modelIDs: ["cc/claude-opus-5", "claude/claude-opus-5"]),
        "aihorde": CatalogProvider(provider: "AI Horde", modelIDs: ["aihorde/2DN"])
    ]

    func testTilesGroupConnectionsAndKeepOrder() {
        let tiles = Dashboard.tiles(connections: [
            Connection(provider: "codex", isActive: false),
            Connection(provider: "claude", isActive: false),
            Connection(provider: "claude", isActive: true, testStatus: "active"),
            Connection(provider: "", isActive: true)
        ], catalog: catalog)
        XCTAssertEqual(tiles.map(\.id), ["codex", "claude"])
        XCTAssertEqual(tiles.map(\.name), ["Codex", "Claude Code"])
        XCTAssertEqual(tiles.map(\.isActive), [false, true])
        XCTAssertEqual(tiles.map(\.accounts.count), [1, 2])
    }

    func testBrokenConnectionIsNotUsable() {
        XCTAssertFalse(Connection(provider: "claude", isActive: true, testStatus: "expired").isUsable)
        XCTAssertTrue(Connection(provider: "claude", isActive: true, testStatus: nil).isUsable)
    }

    func testModelsOnlyFromActiveProviders() {
        let entries = [
            ModelEntry(id: "auto/best-coding", ownedBy: "combo"),
            ModelEntry(id: "cc/claude-opus-5", ownedBy: "claude"),
            ModelEntry(id: "aihorde/2DN", ownedBy: "aihorde"),
            ModelEntry(id: "cc/claude-opus-5", ownedBy: "claude"),
            ModelEntry(id: "claude/claude-opus-5", ownedBy: "renamed")
        ]
        XCTAssertEqual(
            Dashboard.models(entries, activeProviders: ["claude"], catalog: catalog),
            ["cc/claude-opus-5", "claude/claude-opus-5"]
        )
        XCTAssertEqual(Dashboard.models(entries, activeProviders: [], catalog: catalog), [])
    }

    func testSearchMatchesEveryTerm() {
        let models = ["cc/claude-opus-5", "cc/claude-sonnet-5", "cxa/gpt-6"]
        XCTAssertEqual(Dashboard.filter(models, query: "  "), models)
        XCTAssertEqual(Dashboard.filter(models, query: "CLAUDE son"), ["cc/claude-sonnet-5"])
        XCTAssertEqual(Dashboard.filter(models, query: "gemini"), [])
    }

    func testSeriesFillsMissingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 31, hour: 15)))
        let series = Dashboard.series(
            [Analytics.Day(date: "2026-10-30", requests: 3, totalTokens: 124),
             Analytics.Day(date: "2026-09-01", requests: 9, totalTokens: 9)],
            days: 7, today: today, calendar: calendar
        )
        XCTAssertEqual(series.count, 7)
        XCTAssertEqual(series.map(\.tokens), [0, 0, 0, 0, 0, 124, 0])
        XCTAssertEqual(series.last?.date, calendar.startOfDay(for: today))
    }

    func testCompactNumbers() {
        XCTAssertEqual(Dashboard.compact(950), "950")
        XCTAssertEqual(Dashboard.compact(1_000), "1K")
        XCTAssertEqual(Dashboard.compact(1_260), "1.3K")
        XCTAssertEqual(Dashboard.compact(3_400_000), "3.4M")
        XCTAssertEqual(Dashboard.compact(250_000), "250K")
    }

    func testAnalyticsDecodesStringRates() throws {
        let json = #"{"summary":{"totalRequests":3,"totalTokens":124,"successRatePct":"99.5","avgLatencyMs":1691},"#
            + #""dailyTrend":[{"date":"2026-10-30","requests":3,"totalTokens":124}]}"#
        let analytics = try JSONDecoder().decode(Analytics.self, from: Data(json.utf8))
        XCTAssertEqual(analytics.summary?.successRatePct, 99.5)
        XCTAssertEqual(analytics.summary?.totalTokens, 124)
        XCTAssertEqual(analytics.dailyTrend?.first?.requests, 3)
    }

    func testErrorMessageShapes() {
        XCTAssertEqual(OmniRouteClient.errorMessage(in: Data(#"{"error":"nope"}"#.utf8)), "nope")
        XCTAssertEqual(OmniRouteClient.errorMessage(in: Data(#"{"error":{"message":"deep"}}"#.utf8)), "deep")
        XCTAssertNil(OmniRouteClient.errorMessage(in: Data("oops".utf8)))
    }
}
