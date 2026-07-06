import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    planLimitsSection
                    tokensGrid
                    if !store.todayByModel.isEmpty {
                        byModelSection
                    }
                    lastDaysSection
                }
                .padding(14)
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text("Hoy")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(UsageStore.money(store.todayCost))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(UsageStore.tokens(store.todayUsage.total)) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var planLimitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Límites del plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let plan = store.planUsage {
                if let session = plan.fiveHour {
                    LimitRow(label: "Sesión actual (5 h)", window: session)
                }
                if let week = plan.sevenDay {
                    LimitRow(label: "Semana (todos)", window: week)
                }
                if let opusWeek = plan.sevenDayOpus {
                    LimitRow(label: "Semana (Opus)", window: opusWeek)
                }
            } else if let error = store.planError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Consultando…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tokensGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                tokenCell("Input", store.todayUsage.input)
                tokenCell("Output", store.todayUsage.output)
            }
            GridRow {
                tokenCell("Cache write", store.todayUsage.cacheWrite)
                tokenCell("Cache read", store.todayUsage.cacheRead)
            }
        }
    }

    private func tokenCell(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(UsageStore.tokens(count))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var byModelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Por modelo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(store.todayByModel) { model in
                HStack {
                    Text(shortModelName(model.model))
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(UsageStore.tokens(model.usage.total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(UsageStore.money(model.cost))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
    }

    private var lastDaysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Últimos 7 días")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            let maxCost = max(store.lastDays.map(\.cost).max() ?? 0, 0.01)
            ForEach(store.lastDays) { day in
                HStack(spacing: 8) {
                    Text(Self.dayLabel(day.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.tint)
                            .frame(width: max(geometry.size.width * day.cost / maxCost, 2))
                    }
                    .frame(height: 10)
                    Text(UsageStore.money(day.cost))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let lastScanned = store.lastScanned {
                Text("Actualizado \(lastScanned.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if store.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Actualizar")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Salir")
        }
        .padding(10)
    }

    private func shortModelName(_ model: String) -> String {
        model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20[0-9]{6}$", with: "", options: .regularExpression)
    }

    private static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hoy" }
        if Calendar.current.isDateInYesterday(date) { return "Ayer" }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

/// Barra de progreso de una ventana de límite, con % y hora de reinicio.
private struct LimitRow: View {
    let label: String
    let window: LimitWindow

    private var fraction: Double {
        min(max((window.utilization ?? 0) / 100, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(window.utilization ?? 0))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(fraction > 0.85 ? .red : .primary)
            }
            ProgressView(value: fraction)
                .tint(fraction > 0.85 ? .red : fraction > 0.6 ? .orange : .accentColor)
            if let reset = window.resetDate {
                Text("Se reinicia \(Self.resetLabel(reset))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private static func resetLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "a las \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}
