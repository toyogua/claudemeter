import Foundation

struct DayUsage: Identifiable {
    let date: Date
    var usage = TokenUsage()
    var cost = 0.0

    var id: Date { date }
}

struct ModelUsage: Identifiable {
    let model: String
    var usage = TokenUsage()
    var cost = 0.0

    var id: String { model }
}

/// Estado observable: agrega los transcripts en "hoy", desglose por modelo
/// y últimos 7 días. Re-escanea cada 60 segundos (el scanner cachea por
/// archivo, así que el costo del poll es mínimo).
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var todayCost = 0.0
    @Published private(set) var todayUsage = TokenUsage()
    @Published private(set) var todayByModel: [ModelUsage] = []
    @Published private(set) var lastDays: [DayUsage] = []
    @Published private(set) var lastScanned: Date?
    @Published private(set) var isScanning = false
    /// Límites del plan (lo que muestra /usage). nil hasta el primer fetch.
    @Published private(set) var planUsage: PlanUsage?
    @Published private(set) var planError: String?

    private let scanner = UsageScanner()
    private let planClient = PlanLimitsClient()
    private var pollTask: Task<Void, Never>?
    private var lastPlanFetch: Date?
    private var planBackoffUntil: Date?

    private static let pollInterval: Duration = .seconds(60)
    /// El endpoint de límites rate-limita agresivamente: consultar poco.
    private static let planInterval: TimeInterval = 5 * 60
    private static let planBackoff: TimeInterval = 15 * 60

    /// Texto del ícono en la barra de menú: % de uso de la sesión actual
    /// (compacto — los ítems anchos son los primeros que macOS oculta
    /// cuando la barra se llena). El costo y el resto viven en el panel.
    var menuTitle: String {
        if let session = planUsage?.fiveHour?.utilization {
            return "\(Int(session))%"
        }
        return "–"
    }

    init() {
        startPolling()
    }

    func refresh() async {
        isScanning = true
        defer { isScanning = false }

        let scanner = self.scanner
        let entries = await Task.detached(priority: .utility) {
            scanner.scan()
        }.value

        aggregate(entries)
        lastScanned = Date()
        await refreshPlanLimitsIfDue()
    }

    /// Consulta /api/oauth/usage respetando el intervalo y el backoff.
    private func refreshPlanLimitsIfDue() async {
        let now = Date()
        if let backoff = planBackoffUntil, now < backoff { return }
        if let last = lastPlanFetch, now.timeIntervalSince(last) < Self.planInterval { return }
        lastPlanFetch = now
        do {
            planUsage = try await planClient.fetch()
            planError = nil
            planBackoffUntil = nil
        } catch PlanLimitsError.rateLimited {
            planBackoffUntil = now.addingTimeInterval(Self.planBackoff)
            // Se conserva el último dato conocido; sin banner de error.
        } catch {
            planError = error.localizedDescription
        }
    }

    static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func tokens(_ count: Int) -> String {
        switch count {
        case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
        case 1_000...: return String(format: "%.1fk", Double(count) / 1_000)
        default: return "\(count)"
        }
    }

    // MARK: - Internals

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func aggregate(_ entries: [UsageEntry]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var days: [Date: DayUsage] = [:]
        var models: [String: ModelUsage] = [:]
        var todayTotal = TokenUsage()
        var todayTotalCost = 0.0

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp)
            var dayUsage = days[day] ?? DayUsage(date: day)
            dayUsage.usage = dayUsage.usage + entry.usage
            dayUsage.cost += entry.cost
            days[day] = dayUsage

            if day == today {
                todayTotal = todayTotal + entry.usage
                todayTotalCost += entry.cost
                var modelUsage = models[entry.model] ?? ModelUsage(model: entry.model)
                modelUsage.usage = modelUsage.usage + entry.usage
                modelUsage.cost += entry.cost
                models[entry.model] = modelUsage
            }
        }

        todayUsage = todayTotal
        todayCost = todayTotalCost
        todayByModel = models.values.sorted { $0.cost > $1.cost }
        lastDays = (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
            .map { days[$0] ?? DayUsage(date: $0) }
    }
}
