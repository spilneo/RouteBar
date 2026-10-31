import Foundation
@testable import RouteBarKit
import XCTest

final class QuotaTests: XCTestCase {
    /// The shape `GET /api/usage/<connectionId>` returned for a Claude subscription.
    let claude = Data(#"""
    {"plan":"default_claude_ai","quotas":{
      "weekly (7d)":{"used":63,"total":100,"remaining":37,"resetAt":"2026-11-03T17:59:59.764Z","remainingPercentage":37,"unlimited":false},
      "session (5h)":{"used":27,"total":100,"remaining":73,"resetAt":"2026-10-31T05:29:59.764Z","remainingPercentage":73,"unlimited":false},
      "credits":{"used":5,"total":10,"unlimited":false},
      "extra":{"unlimited":true}
    }}
    """#.utf8)

    func testParsesWindowsSoonestResetFirst() throws {
        let windows = Quotas.parse(claude)
        XCTAssertEqual(windows.map(\.label), ["5h", "7d", "Credits"], "unlimited windows are dropped")
        XCTAssertEqual(windows[0].usedPercent, 27)
        XCTAssertEqual(windows[1].usedPercent, 63)
        XCTAssertEqual(windows[2].usedPercent, 50, "falls back to used / total")
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-31T05:29:59Z")).addingTimeInterval(0.764)
        XCTAssertEqual(try XCTUnwrap(windows[0].resetsAt).timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(windows[2].resetsAt)
    }

    func testUnknownShapesYieldNothing() {
        XCTAssertEqual(Quotas.parse(Data("[]".utf8)), [])
        XCTAssertEqual(Quotas.parse(Data(#"{"quotas":{"x":{"note":"no numbers"}}}"#.utf8)), [])
    }

    func testLevels() {
        XCTAssertEqual(QuotaWindow(label: "5h", usedPercent: 79, resetsAt: nil).level, .normal)
        XCTAssertEqual(QuotaWindow(label: "5h", usedPercent: 80, resetsAt: nil).level, .high)
        XCTAssertEqual(QuotaWindow(label: "5h", usedPercent: 95, resetsAt: nil).level, .critical)
    }

    func testMergeKeepsTheBusiestConnection() {
        let merged = Quotas.merge([
            [QuotaWindow(label: "5h", usedPercent: 10, resetsAt: nil), QuotaWindow(label: "7d", usedPercent: 90, resetsAt: nil)],
            [QuotaWindow(label: "5h", usedPercent: 40, resetsAt: nil)]
        ])
        XCTAssertEqual(merged.map(\.label), ["5h", "7d"])
        XCTAssertEqual(merged.map(\.usedPercent), [40, 90])
    }

    func testTilesTakeQuotasOnlyFromUsableConnections() {
        let tiles = Dashboard.tiles(
            connections: [
                Connection(id: "a", provider: "claude", isActive: true),
                Connection(id: "b", provider: "claude", isActive: false)
            ],
            catalog: [:],
            quotas: [
                "a": [QuotaWindow(label: "5h", usedPercent: 20, resetsAt: nil)],
                "b": [QuotaWindow(label: "5h", usedPercent: 99, resetsAt: nil)]
            ]
        )
        XCTAssertEqual(tiles.first?.quotas.map(\.usedPercent), [20], "a disabled connection's limits are not shown")
    }

    func testCountdown() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Dashboard.countdown(to: now.addingTimeInterval(12 * 60 + 30), now: now), "12m")
        XCTAssertEqual(Dashboard.countdown(to: now.addingTimeInterval(4 * 3_600 + 6 * 60), now: now), "4h 6m")
        XCTAssertEqual(Dashboard.countdown(to: now.addingTimeInterval(2 * 86_400 + 7 * 3_600), now: now), "2d 7h")
        XCTAssertEqual(Dashboard.countdown(to: now.addingTimeInterval(-60), now: now), "0m")
    }
}
