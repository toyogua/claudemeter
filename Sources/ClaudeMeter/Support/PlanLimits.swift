import Foundation
import Security

/// Una ventana de límite del plan: % consumido y cuándo se reinicia.
struct LimitWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        return LimitWindow.isoFractional.date(from: resetsAt)
            ?? LimitWindow.isoPlain.date(from: resetsAt)
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain = ISO8601DateFormatter()
}

/// Respuesta de GET /api/oauth/usage — lo mismo que alimenta /usage en
/// Claude Code. Campos desconocidos se ignoran (endpoint no documentado).
struct PlanUsage: Decodable {
    let fiveHour: LimitWindow?
    let sevenDay: LimitWindow?
    let sevenDayOpus: LimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }
}

enum PlanLimitsError: LocalizedError {
    case noCredentials
    case tokenExpired
    case rateLimited
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No encontré credenciales de Claude Code (Keychain ni ~/.claude/.credentials.json)."
        case .tokenExpired:
            return "El token de Claude Code expiró — abrí Claude Code para renovarlo."
        case .rateLimited:
            return "La API de límites pidió pausa (rate limit)."
        case .http(let code):
            return "La API de límites respondió \(code)."
        }
    }
}

/// Lee el token OAuth de Claude Code y consulta el endpoint de límites del
/// plan. El endpoint rate-limita agresivamente: consultarlo con moderación
/// (el store lo hace cada 5 min, con backoff ante 429).
final class PlanLimitsClient {
    private let session: URLSession = .shared

    func fetch() async throws -> PlanUsage {
        let token = try accessToken()

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429
                ? PlanLimitsError.rateLimited
                : PlanLimitsError.http(http.statusCode)
        }
        return try JSONDecoder().decode(PlanUsage.self, from: data)
    }

    // MARK: - Credenciales

    private struct Credentials: Decodable {
        let claudeAiOauth: OAuth?
        struct OAuth: Decodable {
            let accessToken: String?
            /// Epoch en milisegundos.
            let expiresAt: Double?
        }
    }

    /// Keychain ("Claude Code-credentials") con fallback al archivo JSON.
    /// La primera lectura del Keychain dispara el diálogo de permiso de
    /// macOS — "Permitir siempre" y no vuelve a preguntar.
    private func accessToken() throws -> String {
        let data = keychainData() ?? fileData()
        guard let data,
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let oauth = credentials.claudeAiOauth,
              let token = oauth.accessToken
        else { throw PlanLimitsError.noCredentials }
        if let expiresAt = oauth.expiresAt,
           Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
            throw PlanLimitsError.tokenExpired
        }
        return token
    }

    private func keychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private func fileData() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/.credentials.json")
        return try? Data(contentsOf: url)
    }
}
