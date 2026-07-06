import XCTest
@testable import ClaudeMeter

final class UsageScannerTests: XCTestCase {
    func testParsesAssistantLineWithUsage() throws {
        let line = Data("""
        {"type":"assistant","timestamp":"2026-07-06T12:00:00.123Z","requestId":"req_1",\
        "cwd":"/Users/x/proyecto","message":{"id":"msg_1","model":"claude-fable-5",\
        "usage":{"input_tokens":10,"output_tokens":200,\
        "cache_creation_input_tokens":100,"cache_read_input_tokens":5000}}}
        """.utf8)

        let parsed = try XCTUnwrap(UsageScanner.parseLine(line))

        XCTAssertEqual(parsed.key, "msg_1:req_1")
        XCTAssertEqual(parsed.entry.model, "claude-fable-5")
        XCTAssertEqual(parsed.entry.usage, TokenUsage(input: 10, output: 200,
                                                      cacheWrite: 100, cacheRead: 5000))
    }

    func testIgnoresNonAssistantAndSyntheticLines() {
        let user = Data(#"{"type":"user","timestamp":"2026-07-06T12:00:00Z","message":{}}"#.utf8)
        XCTAssertNil(UsageScanner.parseLine(user))

        let synthetic = Data("""
        {"type":"assistant","timestamp":"2026-07-06T12:00:00Z",\
        "message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}
        """.utf8)
        XCTAssertNil(UsageScanner.parseLine(synthetic))

        XCTAssertNil(UsageScanner.parseLine(Data("no-es-json".utf8)))
    }

    func testTimestampWithoutFractionalSecondsParses() throws {
        let line = Data("""
        {"type":"assistant","timestamp":"2026-07-06T12:00:00Z",\
        "message":{"id":"m","model":"claude-opus-4-8","usage":{"input_tokens":5,"output_tokens":5}}}
        """.utf8)
        XCTAssertNotNil(UsageScanner.parseLine(line))
    }
}
