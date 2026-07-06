import XCTest
@testable import ClaudeMeter

final class PricingTests: XCTestCase {
    func testModelMatching() {
        XCTAssertEqual(Pricing.pricing(for: "claude-fable-5"), ModelPricing(input: 10, output: 50))
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-8"), ModelPricing(input: 5, output: 25))
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-1"), ModelPricing(input: 15, output: 75))
        XCTAssertEqual(Pricing.pricing(for: "claude-sonnet-5"), ModelPricing(input: 3, output: 15))
        XCTAssertEqual(Pricing.pricing(for: "claude-haiku-4-5-20251001"), ModelPricing(input: 1, output: 5))
    }

    func testCacheMultipliers() {
        let opus = Pricing.pricing(for: "claude-opus-4-8")
        XCTAssertEqual(opus.cacheWrite, 6.25)  // 5 * 1.25
        XCTAssertEqual(opus.cacheRead, 0.5)    // 5 * 0.1
    }

    func testCostCalculation() {
        // 1M de cada categoría en Opus 4.8: 5 + 25 + 6.25 + 0.5 = 36.75
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000,
                               cacheWrite: 1_000_000, cacheRead: 1_000_000)
        XCTAssertEqual(Pricing.cost(model: "claude-opus-4-8", usage: usage), 36.75, accuracy: 0.001)
    }
}
