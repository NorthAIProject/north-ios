import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// One area of the Progress tab in depth, for the window the tab is showing.
struct InsightsDomainView: View {
    let domain: InsightsDomain
    let range: String
    var service: InsightsDomainServicing = InsightsService()

    var body: some View {
        Group {
            switch domain {
            case .body: DomainLoader(range: range, load: service.body) { BodyPage(model: $0) }
            case .mind: DomainLoader(range: range, load: service.mind) { MindPage(model: $0) }
            case .progress: DomainLoader(range: range, load: service.progress) { ProgressPage(model: $0) }
            case .training: DomainLoader(range: range, load: service.training) { TrainingPage(model: $0) }
            case .nutrition: DomainLoader(range: range, load: service.nutrition) { NutritionPage(model: $0) }
            case .coach: DomainLoader(range: range, load: service.coach) { CoachPage(model: $0) }
            case .spend: DomainLoader(range: range, load: service.spend) { SpendPage(model: $0) }
            case .timeline: TimelinePage(range: range, service: service)
            }
        }
        .navigationTitle(domain.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Loads one page for a window and shows it, or says why it could not.
private struct DomainLoader<Model: Sendable, Page: View>: View {
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

// MARK: Pages

private struct BodyPage: View {
    let model: InsightsBody

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Water", (Double(model.totalWaterML) / 1000).formatted(.number.precision(.fractionLength(1))) + " L"),
                    ("Nights", "\(model.nights)"),
                    ("Sleep", model.hasSleep ? hours(model.avgSleepMinutes) : "–"),
                    ("Quality", model.qualityCount > 0 ? model.avgQuality.formatted(.number.precision(.fractionLength(1))) + " / 5" : "–"),
                ])
            } footer: {
                if model.qualityCount > 0 && model.qualityCount < model.nights {
                    Text("Quality is the average of the \(model.qualityCount) nights you rated.")
                }
            }
            ChartSection(title: "Water (ml)", chart: model.water, hasData: model.hasWater)
            ChartSection(title: "Hours Slept", chart: model.sleep, hasData: model.hasSleep, style: .line)
            if model.hasHabits {
                Section {
                    ForEach(model.habits, id: \.name) { habit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(habit.name)
                                Text("\(habit.kept) of \(habit.scheduled) · \(habit.streak)-day streak")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(habit.rate)%").font(.subheadline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Habits · \(model.adherence)% kept")
                }
            }
        }
    }

    private func hours(_ minutes: Double) -> String {
        (minutes / 60).formatted(.number.precision(.fractionLength(1))) + " h"
    }
}

private struct MindPage: View {
    let model: InsightsMind

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Check-ins", "\(model.checkInCount)"),
                    ("Mood", model.hasCheckIns ? model.avgMood.formatted(.number.precision(.fractionLength(1))) : "–"),
                    ("Energy", model.hasCheckIns ? model.avgEnergy.formatted(.number.precision(.fractionLength(1))) : "–"),
                    ("Journal", "\(model.journalCount)"),
                ])
            }
            Section("Mood and Energy") {
                if model.hasCheckIns {
                    MoodEnergyChart(labels: model.labels, mood: model.mood, energy: model.energy)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                } else {
                    EmptyRow(text: "No check-ins in this window.")
                }
            }
            ChartSection(title: "Journal Entries", chart: model.journal, hasData: model.hasJournal)
        }
    }
}

private struct ProgressPage: View {
    let model: InsightsProgress

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Active", "\(model.activeCount)"),
                    ("Average", "\(model.avgProgress)%"),
                    ("Overdue", "\(model.overdue)"),
                    ("Streak", "\(model.streak) d"),
                ])
            }
            if !model.goals.isEmpty {
                Section("Goals") {
                    ForEach(model.goals, id: \.id) { goal in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(goal.title)
                                Spacer()
                                Text(goal.hasProgress ? "\(goal.progress)%" : "–").font(.subheadline.monospacedDigit())
                            }
                            if goal.hasProgress {
                                ProgressView(value: Double(goal.progress), total: 100).tint(NorthColor.signal)
                            }
                            if !goal.deadline.isEmpty {
                                Text(goal.overdue ? "Overdue · \(goal.deadline)" : "Due \(goal.deadline)")
                                    .font(.caption)
                                    .foregroundStyle(goal.overdue ? .red : .secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            SegmentSection(title: "By Status", segments: model.statuses)
            ChartSection(title: "Updates", chart: model.notes, hasData: model.hasNotes)
        }
    }
}

private struct TrainingPage: View {
    let model: InsightsTraining

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Sessions", "\(model.sessionCount)"),
                    ("Time", model.totalTime),
                    ("Burned", model.calories.formatted(.number.precision(.fractionLength(0))) + " kcal"),
                ])
                if model.delta.hasPrior {
                    DeltaText(direction: model.delta.direction, pct: model.delta.pct)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ChartSection(title: "Calories Burned", chart: model.burn, hasData: model.hasSessions)
            SegmentSection(title: "Activities", segments: model.kinds)
            if model.hasSessions {
                Section("Sessions") {
                    ForEach(Array(model.sessions.enumerated()), id: \.offset) { _, session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                Text(session.at.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(session.duration).font(.subheadline.monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct NutritionPage: View {
    let model: InsightsNutrition

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Calories", model.avgCalories.isEmpty ? "–" : model.avgCalories),
                    ("Protein", model.avgProtein.isEmpty ? "–" : model.avgProtein),
                    ("Days", "\(model.daysLogged)"),
                    ("Entries", "\(model.entries)"),
                ])
            } footer: {
                if model.hasGoal {
                    Text("A day on average. Your goal is \(model.goalCalories) and \(model.goalProtein) protein.")
                } else {
                    Text("A day on average. Set a goal in Settings → Body & Goal to be judged against it.")
                }
            }
            ChartSection(title: "Calories", chart: model.calories, hasData: model.hasData)
            if model.hasSplit {
                SegmentSection(title: "Macros (g)", segments: model.macros)
            }
            HighlightsSection(highlights: model.highlights)
        }
    }
}

private struct CoachPage: View {
    let model: InsightsCoach

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("You", "\(model.yourMessages)"),
                    ("Coach", "\(model.coachReplies)"),
                    ("Helpful", model.hasRatings ? "\(model.helpfulRate)%" : "–"),
                ])
            } footer: {
                if model.hasRatings {
                    Text("Of the \(model.rated) replies you rated.")
                }
                if model.truncated {
                    Text("Counted from your most recent messages only.")
                }
            }
            ChartSection(title: "Messages", chart: model.chart, hasData: model.hasData)
            HighlightsSection(highlights: model.highlights)
        }
    }
}

private struct SpendPage: View {
    let model: InsightsSpend

    var body: some View {
        List {
            Section {
                StatGrid(stats: [
                    ("Cost", model.totalCost),
                    ("Generations", "\(model.generations)"),
                    ("Tokens", model.totalTokens.formatted(.number.notation(.compactName))),
                ])
            }
            if model.hasData {
                SpendSection(title: "Where", lines: model.surfaces)
                SpendSection(title: "Models", lines: model.models)
            } else {
                Section { EmptyRow(text: "Nothing generated in this window.") }
            }
        }
    }
}

private struct TimelinePage: View {
    let range: String
    let service: InsightsDomainServicing

    @State private var kind: String?
    @State private var model: InsightsTimeline?
    @State private var error: String?

    var body: some View {
        List {
            if let model {
                if model.entries.isEmpty {
                    EmptyRow(text: "Nothing logged in this window.")
                }
                ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.label).northEyebrow()
                            Spacer()
                            Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.title)
                        if !entry.detail.isEmpty {
                            Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if model.overflow {
                    Text("Showing the most recent entries. Pick a shorter window to see the rest.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let error {
                ContentUnavailableView("This did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .toolbar {
            if let filters = model?.filters, filters.count > 1 {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Show", selection: $kind) {
                        ForEach(filters, id: \.key) { filter in
                            Text("\(filter.label) (\(filter.count))").tag(filter.key.isEmpty ? nil : Optional(filter.key))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task(id: "\(range)|\(kind ?? "")") { await refresh() }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        do {
            model = try await service.timeline(kind: kind, range: range)
            error = nil
        } catch {
            if model == nil { self.error = error.localizedDescription }
        }
    }
}

// MARK: Parts

/// A few headline numbers side by side.
private struct StatGrid: View {
    let stats: [(label: String, value: String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, stats.count), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stats[index].label).northEyebrow()
                            Text(stats[index].value).northDisplayNumber(.title2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChartSection: View {
    enum Style { case bar, line }

    let title: String
    let chart: InsightsChart
    let hasData: Bool
    var style: Style = .bar

    var body: some View {
        Section(title) {
            if hasData {
                SeriesChart(chart: chart, style: style)
                    .frame(height: 180)
                    .padding(.vertical, 8)
            } else {
                EmptyRow(text: "Nothing logged in this window.")
            }
        }
    }
}

private struct SeriesChart: View {
    let chart: InsightsChart
    let style: ChartSection.Style

    var body: some View {
        let points = chart.series.flatMap { series in
            series.values.enumerated().map { index, value in
                (series: series.label, label: chart.labels.indices.contains(index) ? chart.labels[index] : "\(index)", value: value)
            }
        }
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            switch style {
            case .bar:
                BarMark(x: .value("When", point.label), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            case .line:
                LineMark(x: .value("When", point.label), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Series", point.series))
            }
        }
        .chartForegroundStyleScale(range: [NorthColor.signal, Color.secondary])
        .chartLegend(chart.series.count > 1 ? .visible : .hidden)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
    }
}

/// Mood and energy, 1-5. A bucket without a check-in is left out rather than
/// drawn as a zero, which would read as the worst possible day.
private struct MoodEnergyChart: View {
    let labels: [String]
    let mood: [Int]
    let energy: [Int]

    var body: some View {
        let points = labels.enumerated().flatMap { index, label in
            [("Mood", label, mood[safe: index] ?? 0), ("Energy", label, energy[safe: index] ?? 0)]
        }.filter { $0.2 > 0 }
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("When", point.1), y: .value("Score", point.2))
                .foregroundStyle(by: .value("Series", point.0))
                .symbol(by: .value("Series", point.0))
        }
        .chartForegroundStyleScale(range: [NorthColor.signal, Color.secondary])
        .chartYScale(domain: 1...5)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
    }
}

private struct SegmentSection: View {
    let title: String
    let segments: [InsightsSegment]

    var body: some View {
        if segments.contains(where: { $0.value > 0 }) {
            Section(title) {
                Chart(segments, id: \.label) { segment in
                    SectorMark(angle: .value("Count", segment.value), innerRadius: .ratio(0.6))
                        .foregroundStyle(by: .value("Label", segment.label))
                }
                .frame(height: 180)
                .padding(.vertical, 8)
                ForEach(segments, id: \.label) { segment in
                    LabeledContent(segment.label, value: "\(segment.value)")
                }
            }
        }
    }
}

private struct SpendSection: View {
    let title: String
    let lines: [Components.Schemas.InsightsSpendLine]

    var body: some View {
        Section(title) {
            ForEach(lines, id: \.label) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(line.label)
                        Spacer()
                        Text(line.cost).font(.subheadline.monospacedDigit())
                    }
                    ProgressView(value: Double(line.pct), total: 100).tint(NorthColor.signal)
                    Text("\(line.generations) generations · \(line.tokens.formatted(.number.notation(.compactName))) tokens")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct HighlightsSection: View {
    let highlights: [String]

    var body: some View {
        if !highlights.isEmpty {
            Section("Highlights") {
                ForEach(highlights, id: \.self) { Text($0).font(.subheadline) }
            }
        }
    }
}

private struct EmptyRow: View {
    let text: String

    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
