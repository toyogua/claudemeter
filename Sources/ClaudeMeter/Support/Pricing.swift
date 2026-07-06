import Foundation

/// Tokens consumidos, en las cuatro categorías que factura Anthropic.
struct TokenUsage: Equatable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }
}

/// USD por millón de tokens. Cache write = 1.25x input (TTL 5 min),
/// cache read = 0.1x input — multiplicadores oficiales de Anthropic.
struct ModelPricing: Equatable {
    let input: Double
    let output: Double

    var cacheWrite: Double { input * 1.25 }
    var cacheRead: Double { input * 0.1 }
}

/// Precios vigentes a julio 2026 (platform.claude.com/docs/en/pricing).
enum Pricing {
    static func pricing(for model: String) -> ModelPricing {
        let id = model.lowercased()
        if id.contains("fable") || id.contains("mythos") {
            return ModelPricing(input: 10, output: 50)
        }
        if id.contains("opus-4-8") || id.contains("opus-4-7")
            || id.contains("opus-4-6") || id.contains("opus-4-5") {
            return ModelPricing(input: 5, output: 25)
        }
        if id.contains("opus") {
            // Opus 4.1 y anteriores
            return ModelPricing(input: 15, output: 75)
        }
        if id.contains("sonnet") {
            return ModelPricing(input: 3, output: 15)
        }
        if id.contains("3-5-haiku") {
            return ModelPricing(input: 0.8, output: 4)
        }
        if id.contains("3-haiku") {
            return ModelPricing(input: 0.25, output: 1.25)
        }
        if id.contains("haiku") {
            return ModelPricing(input: 1, output: 5)
        }
        // Modelo desconocido: asumir tier Opus actual para no subestimar.
        return ModelPricing(input: 5, output: 25)
    }

    static func cost(model: String, usage: TokenUsage) -> Double {
        let p = pricing(for: model)
        return (Double(usage.input) * p.input
            + Double(usage.output) * p.output
            + Double(usage.cacheWrite) * p.cacheWrite
            + Double(usage.cacheRead) * p.cacheRead) / 1_000_000
    }
}
