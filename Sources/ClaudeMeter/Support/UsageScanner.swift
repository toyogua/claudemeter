import Foundation

/// Un mensaje del asistente con su consumo, extraído de los transcripts.
struct UsageEntry {
    let timestamp: Date
    let model: String
    let usage: TokenUsage

    var cost: Double { Pricing.cost(model: model, usage: usage) }
}

/// Lee los transcripts de Claude Code (~/.claude/projects/**/*.jsonl) y
/// extrae el consumo por mensaje. Cachea por archivo (mtime + tamaño) para
/// no re-parsear lo que no cambió, y deduplica globalmente por
/// message.id + requestId (el mismo mensaje puede aparecer en varios
/// archivos tras un resume o un fork de sesión).
final class UsageScanner {
    private let root: URL
    private var fileCache: [String: CachedFile] = [:]

    private struct CachedFile {
        let modified: Date
        let size: Int
        let entries: [(key: String?, entry: UsageEntry)]
    }

    /// Ventana máxima de interés: archivos más viejos se ignoran de plano.
    private static let maxAge: TimeInterval = 8 * 24 * 3600

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects")) {
        self.root = root
    }

    func scan(now: Date = Date()) -> [UsageEntry] {
        let files = jsonlFiles()
        var seen = Set<String>()
        var result: [UsageEntry] = []
        var liveCache: [String: CachedFile] = [:]

        for file in files {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let modified = attrs[.modificationDate] as? Date,
                  let size = (attrs[.size] as? NSNumber)?.intValue
            else { continue }
            guard now.timeIntervalSince(modified) < Self.maxAge else { continue }

            let cached: CachedFile
            if let hit = fileCache[file.path], hit.modified == modified, hit.size == size {
                cached = hit
            } else {
                cached = CachedFile(modified: modified, size: size, entries: parse(file: file))
            }
            liveCache[file.path] = cached

            for (key, entry) in cached.entries {
                if let key {
                    guard seen.insert(key).inserted else { continue }
                }
                result.append(entry)
            }
        }
        fileCache = liveCache
        return result
    }

    // MARK: - Internals

    private func jsonlFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            return url
        }
    }

    private func parse(file: URL) -> [(key: String?, entry: UsageEntry)] {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return text.split(separator: "\n").compactMap { line in
            Self.parseLine(Data(line.utf8))
        }
    }

    /// Parseo de una línea del transcript (público para tests).
    static func parseLine(_ data: Data) -> (key: String?, entry: UsageEntry)? {
        guard let raw = try? JSONDecoder().decode(RawLine.self, from: data),
              raw.type == "assistant",
              let message = raw.message,
              let model = message.model, !model.hasPrefix("<"),
              let rawUsage = message.usage,
              let timestamp = raw.timestamp.flatMap(parseTimestamp)
        else { return nil }

        let usage = TokenUsage(
            input: rawUsage.inputTokens ?? 0,
            output: rawUsage.outputTokens ?? 0,
            cacheWrite: rawUsage.cacheCreationInputTokens ?? 0,
            cacheRead: rawUsage.cacheReadInputTokens ?? 0
        )
        guard usage.total > 0 else { return nil }

        let key = message.id.map { "\($0):\(raw.requestId ?? "")" }
        return (key, UsageEntry(timestamp: timestamp, model: model, usage: usage))
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain = ISO8601DateFormatter()

    private static func parseTimestamp(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }

    // El transcript mezcla convenciones: claves camelCase arriba,
    // snake_case dentro de usage.
    private struct RawLine: Decodable {
        let type: String?
        let timestamp: String?
        let requestId: String?
        let message: RawMessage?
    }

    private struct RawMessage: Decodable {
        let id: String?
        let model: String?
        let usage: RawUsage?
    }

    private struct RawUsage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
