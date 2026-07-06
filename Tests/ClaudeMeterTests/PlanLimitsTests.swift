import XCTest
@testable import ClaudeMeter

final class PlanLimitsTests: XCTestCase {
    func testDecodesUsageResponse() throws {
        let json = Data("""
        {
          "five_hour": { "utilization": 34, "resets_at": "2026-07-06T22:00:00Z" },
          "seven_day": { "utilization": 12.5, "resets_at": "2026-07-09T18:00:00.000Z" },
          "seven_day_opus": { "utilization": 5, "resets_at": "2026-07-09T18:00:00Z" },
          "campo_desconocido": { "algo": true }
        }
        """.utf8)

        let usage = try JSONDecoder().decode(PlanUsage.self, from: json)

        XCTAssertEqual(usage.fiveHour?.utilization, 34)
        XCTAssertEqual(usage.sevenDay?.utilization, 12.5)
        XCTAssertEqual(usage.sevenDayOpus?.utilization, 5)
        XCTAssertNotNil(usage.fiveHour?.resetDate)
        XCTAssertNotNil(usage.sevenDay?.resetDate)
    }

    func testMissingWindowsDecodeAsNil() throws {
        let usage = try JSONDecoder().decode(PlanUsage.self, from: Data("{}".utf8))
        XCTAssertNil(usage.fiveHour)
        XCTAssertNil(usage.sevenDay)
        XCTAssertNil(usage.sevenDayOpus)
    }
}
