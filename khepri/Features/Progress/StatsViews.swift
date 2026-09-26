import Charts
import NorthAPI
import NorthKit
import SwiftUI

typealias StatsSleep = Components.Schemas.StatsSleep
typealias StatsCardio = Components.Schemas.StatsCardio
typealias StatsEating = Components.Schemas.StatsEating
typealias StatsPatterns = Components.Schemas.StatsPatterns

/// Sleep, cardio, eating and patterns: the same numbers as the web's
/// insights pages, one endpoint each.
protocol StatsServicing: Sendable {
    func sleep(range: String?) async throws -> StatsSleep
    func cardio(range: String?) async throws -> StatsCardio
    func eating(range: String?) async throws -> StatsEating
    func patterns(range: String?) async throws -> StatsPatterns
}

struct StatsService: StatsServicing {
    var api: Client = API.shared

    func sleep(range: String?) async throws -> StatsSleep {
        try await NorthAPI.call { try await api.getSleepStats(query: .init(range: range)).ok.body.json }
    }

    func cardio(range: String?) async throws -> StatsCardio {
        try await NorthAPI.call { try await api.getCardioStats(query: .init(range: range)).ok.body.json }
    }

    func eating(range: String?) async throws -> StatsEating {
        try await NorthAPI.call { try await api.getEatingStats(query: .init(range: range)).ok.body.json }
    }

    func patterns(range: String?) async throws -> StatsPatterns {
        try await NorthAPI.call { try await api.getPatterns(query: .init(range: range)).ok.body.json }
    }
}

/// Formatting shared by the stats pages.
enum StatsFormat {
    static func hm(_ minutes: Int) -> String {
        minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
    }

    static func pace(_ seconds: Double) -> String {
        guard seconds > 0 else { return "–" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d /km", s / 60, s % 60)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// "Sep 26" from a "2026-09-26" date.
    static func shortDate(_ iso: String) -> String {
        guard let date = CalendarDay.date(from: iso) else { return iso }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static let slotNames: [String: String] = [
        "morning": "Morning (before 11)", "midday": "Midday (11–15)", "afternoon": "Afternoon (15–18)",
        "evening": "Evening (18–21)", "late": "Late (after 21)",
    ]
}

/// Loads one stats page for a window and shows it, or says why not.
struct StatsLoader<Model: Sendable, Page: View>: View {
    let range: String
    let load: @Sendable (String?) async throws -> Model
    @ViewBuilder let page: (Model) -> Page

    @State private var model: Model?
    @State private var error: String?

    var body: some View {
        Group {
            if let model {
                page(model)
            } else if let error {
                ContentUnavailableView("This did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .task(id: range) { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            model = try await load(range)
            error = nil
        } catch {
            if model == nil { self.error = error.localizedDescription }
        }
    }
}

private struct Tile: View {
    let label: String
    let value: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).northEyebrow()
            Text(value).northDisplayNumber(.title2)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ShareBar: View {
    let label: String
    let value: String
    let fraction: Double
    var color: Color = NorthColor.signal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(color).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sleep

struct SleepStatsPage: View {
    let model: StatsSleep

    var body: some View {
        List {
            if model.nights.isEmpty {
                ContentUnavailableView("No sleep in this window", systemImage: "moon.zzz",
                                       description: Text("Sync Apple Health, or log a night on My Day."))
            } else {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Tile(label: "Average", value: StatsFormat.hm(model.avgMinutes), note: "\(model.nights.count) nights")
                            Tile(label: "Sleep debt", value: StatsFormat.hm(model.debtMinutes), note: "last 7 nights")
                        }
                        GridRow {
                            Tile(label: "8h or more", value: "\(model.nightsOnTarget)/\(model.nights.count)")
                            if model.hasTimes {
                                Tile(label: "Bedtime", value: model.avgBedtime, note: "up at \(model.avgWake)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Each Night") {
                    Chart(model.nights, id: \.date) { night in
                        BarMark(x: .value("Night", StatsFormat.shortDate(night.date)), y: .value("Hours", Double(night.minutes) / 60))
                            .foregroundStyle(Double(night.minutes) >= Double(model.targetMinutes) ? NorthColor.Day.sleep : NorthColor.Day.sleep.opacity(0.55))
                        RuleMark(y: .value("Target", Double(model.targetMinutes) / 60))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(.secondary)
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }
                Section {
                    if model.hasTimes {
                        LabeledContent("Bedtime", value: "\(model.avgBedtime) ±\(StatsFormat.hm(model.bedtimeSpreadMinutes))")
                        LabeledContent("Wake time", value: "\(model.avgWake) ±\(StatsFormat.hm(model.wakeSpreadMinutes))")
                    }
                    if model.weekdayAvgMinutes > 0 { LabeledContent("Weekdays", value: StatsFormat.hm(model.weekdayAvgMinutes)) }
                    if model.weekendAvgMinutes > 0 { LabeledContent("Weekends", value: StatsFormat.hm(model.weekendAvgMinutes)) }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("How much bedtime and wake time vary matters about as much as how long you sleep.")
                }
                let stages = StageShare.list(model.stageShare.additionalProperties)
                if !stages.isEmpty {
                    Section("Stages") {
                        ForEach(stages) { stage in
                            ShareBar(label: stage.name, value: StatsFormat.percent(stage.share), fraction: stage.share,
                                     color: NorthColor.Day.sleep)
                        }
                    }
                }
            }
        }
    }
}

private struct StageShare: Identifiable {
    let id: String
    let name: String
    let share: Double

    static func list(_ shares: [String: Double]) -> [StageShare] {
        [("deep", "Deep"), ("rem", "REM"), ("core", "Core")].compactMap { key, name in
            shares[key].map { StageShare(id: key, name: name, share: $0) }
        }
    }
}

// MARK: - Cardio

struct CardioStatsPage: View {
    let model: StatsCardio

    var body: some View {
        List {
            if model.sessions == 0 && model.restingHeartRate.isEmpty {
                ContentUnavailableView("No cardio in this window", systemImage: "figure.run",
                                       description: Text("Runs, rides and walks from Apple Health, Strava or the app show up here."))
            } else {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Tile(label: "Sessions", value: "\(model.sessions)")
                            Tile(label: "Time", value: StatsFormat.hm(model.minutes))
                        }
                        if model.distanceKm > 0 || model.kcal > 0 {
                            GridRow {
                                Tile(label: "Distance", value: String(format: "%.1f km", model.distanceKm))
                                Tile(label: "Burned", value: "\(Int(model.kcal)) kcal")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                let weekly = model.distanceKm > 0 ? model.weeklyKm : model.weeklyMinutes
                if weekly.count > 1 {
                    Section(model.distanceKm > 0 ? "Distance per Week" : "Time per Week") {
                        Chart(weekly, id: \.date) { week in
                            BarMark(x: .value("Week", StatsFormat.shortDate(week.date)), y: .value("Value", week.value))
                                .foregroundStyle(NorthColor.Day.move)
                        }
                        .frame(height: 160)
                        .padding(.vertical, 8)
                    }
                }
                if !model.byKind.isEmpty {
                    let most = Double(model.byKind.map(\.minutes).max() ?? 1)
                    Section("By Activity") {
                        ForEach(model.byKind, id: \.name) { kind in
                            ShareBar(label: "\(kind.name) (\(kind.sessions))",
                                     value: StatsFormat.hm(kind.minutes) + (kind.distanceKm > 0 ? String(format: " · %.1f km", kind.distanceKm) : ""),
                                     fraction: Double(kind.minutes) / max(most, 1), color: NorthColor.Day.move)
                        }
                    }
                }
                if model.runs.count > 0 {
                    Section {
                        LabeledContent("Runs", value: "\(model.runs.count)")
                        if model.runs.distanceKm > 0 {
                            LabeledContent("Distance", value: String(format: "%.1f km", model.runs.distanceKm))
                            LabeledContent("Longest", value: String(format: "%.1f km", model.runs.longestKm))
                        }
                        if model.runs.avgPaceSeconds > 0 {
                            LabeledContent("Average pace", value: StatsFormat.pace(model.runs.avgPaceSeconds))
                            LabeledContent("Best pace", value: StatsFormat.pace(model.runs.bestPaceSeconds))
                        }
                        if model.runs.best5kSeconds > 0 {
                            LabeledContent("Best 5K", value: StatsFormat.duration(model.runs.best5kSeconds))
                        }
                    } header: {
                        Text("Running")
                    } footer: {
                        Text("Paces are per kilometre, over runs of at least 1 km.")
                    }
                }
                HeartSection(model: model)
                if !model.recent.isEmpty {
                    Section("Recent") {
                        ForEach(Array(model.recent.enumerated()), id: \.offset) { _, session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.name)
                                    Text(session.at, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(session.distanceKm > 0 ? String(format: "%.1f km", session.distanceKm) : StatsFormat.hm(session.minutes))
                                        .font(.subheadline.monospacedDigit())
                                    if session.paceSeconds > 0 {
                                        Text(StatsFormat.pace(session.paceSeconds)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

private struct HeartSection: View {
    let model: StatsCardio

    private struct Metric: Identifiable {
        let id: String
        let unit: String
        let values: [Components.Schemas.StatsDayValue]
        let decimals: Int
    }

    var body: some View {
        let rows = [
            Metric(id: "Resting heart rate", unit: "bpm", values: model.restingHeartRate, decimals: 0),
            Metric(id: "HRV", unit: "ms", values: model.hrv, decimals: 0),
            Metric(id: "VO2 max", unit: "", values: model.vo2Max, decimals: 1),
        ].filter { !$0.values.isEmpty }
        if !rows.isEmpty {
            Section("Heart") {
                ForEach(rows) { metric in
                    let label = metric.id
                    let unit = metric.unit
                    let values = metric.values
                    let decimals = metric.decimals
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(label) {
                            Text("\(values.last!.value.formatted(.number.precision(.fractionLength(decimals)))) \(unit)")
                                .monospacedDigit()
                        }
                        if values.count > 1 {
                            Chart(values, id: \.date) { v in
                                LineMark(x: .value("Day", StatsFormat.shortDate(v.date)), y: .value(label, v.value))
                                    .interpolationMethod(.monotone)
                                    .foregroundStyle(NorthColor.Day.move)
                            }
                            .chartXAxis(.hidden)
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 60)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Eating

/// How you eat: loaded beside the Nutrition page's own figures.
struct EatingSections: View {
    let range: String
    var service: StatsServicing = StatsService()

    @State private var model: StatsEating?

    var body: some View {
        Group {
            if let model, model.daysLogged > 0 {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            if model.goalKcal > 0 {
                                Tile(label: "On target", value: "\(model.onTargetDays)/\(model.daysLogged)", note: "within 10% of \(Int(model.goalKcal)) kcal")
                            }
                            if model.goalProteinG > 0 {
                                Tile(label: "Protein met", value: "\(model.proteinDays)/\(model.daysLogged)", note: "goal \(Int(model.goalProteinG)) g")
                            }
                        }
                        GridRow {
                            if model.proteinPerKg > 0 {
                                Tile(label: "Protein per kg", value: String(format: "%.1f g", model.proteinPerKg))
                            }
                            Tile(label: "Late eating", value: "\(model.lateDays) days", note: "after your kitchen closes")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("How You Eat")
                }
                Section("When the Calories Land") {
                    ForEach(model.bySlot, id: \.key) { slot in
                        ShareBar(label: StatsFormat.slotNames[slot.key] ?? slot.key, value: StatsFormat.percent(slot.share),
                                 fraction: slot.share, color: NorthColor.Day.food)
                    }
                }
                if !model.topFoods.isEmpty {
                    Section("Most Logged") {
                        ForEach(model.topFoods, id: \.label) { food in
                            LabeledContent(food.label) {
                                Text("×\(food.count) · \(Int(food.kcal)) kcal").monospacedDigit()
                            }
                        }
                    }
                }
                if model.weekdayKcal > 0 && model.weekendKcal > 0 {
                    Section("Weekdays and Weekends") {
                        LabeledContent("Weekdays", value: "\(Int(model.weekdayKcal)) kcal")
                        LabeledContent("Weekends", value: "\(Int(model.weekendKcal)) kcal")
                    }
                }
            }
        }
        .task(id: range) { model = try? await service.eating(range: range) }
    }
}

// MARK: - Patterns

struct PatternsPage: View {
    let model: StatsPatterns

    var body: some View {
        List {
            Section {
                Text("How the things you log move together over the last \(model.days) days. Each compares two groups of days: it shows what went together, not what caused what.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if model.findings.isEmpty {
                ContentUnavailableView("Nothing stands out yet", systemImage: "sparkles",
                                       description: Text("Patterns need at least three days on each side. Keep logging sleep, caffeine, meals and check-ins."))
            }
            ForEach(model.findings, id: \.key) { finding in
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(finding.title).font(.headline)
                        Text(finding.detail).font(.subheadline).foregroundStyle(.secondary)
                        let most = max(abs(finding.a.mean), abs(finding.b.mean), 1)
                        ShareBar(label: "\(finding.a.label) (\(finding.a.days))", value: value(finding.a.mean, unit: finding.unit),
                                 fraction: abs(finding.a.mean) / most)
                        ShareBar(label: "\(finding.b.label) (\(finding.b.days))", value: value(finding.b.mean, unit: finding.unit),
                                 fraction: abs(finding.b.mean) / most, color: .secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func value(_ mean: Double, unit: String) -> String {
        unit == "min" ? StatsFormat.hm(Int(mean.rounded())) : "\(mean.formatted(.number.precision(.fractionLength(1))))\(unit)"
    }
}
