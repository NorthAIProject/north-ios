import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// The Progress tab: how each part of life is going over a window, the few
/// numbers worth watching, and the health data Apple Health sends.
struct InsightsScreen: View {
    @State private var store = InsightsStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Progress")
                .toolbar {
                    if let options = store.summary?.range.options, !options.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Picker("Range", selection: $store.range) {
                                ForEach(options, id: \.key) { Text($0.label).tag($0.key) }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                .navigationDestination(for: MetricRoute.self) { route in
                    MetricDetailView(key: route.key, range: store.range, service: store.service)
                }
                .navigationDestination(for: InsightsDomain.self) { domain in
                    InsightsDomainView(domain: domain, range: store.range)
                }
                .navigationDestination(for: AreasRoute.self) { _ in
                    AreasScreen()
                }
                .navigationDestination(for: ConsistencyRoute.self) { _ in
                    ConsistencyPage(service: store.service)
                }
                .refreshable { await store.load() }
        }
        .task(id: store.range) { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Progress did not load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
        case .ready:
            if let summary = store.summary {
                SummaryList(summary: summary, health: store.health, recovery: store.recovery)
            }
        }
    }
}

struct MetricRoute: Hashable {
    let key: String
}

private struct SummaryList: View {
    let summary: InsightsSummary
    let health: [InsightsHealthMetric]
    let recovery: InsightsRecovery?

    var body: some View {
        List {
            if summary.empty {
                Section {
                    Text("Nothing is logged for this window yet. Check-ins, sleep, water and workouts fill this in, and so does Apple Health once it is connected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if summary.judged > 0 {
                Section {
                    Text("\(summary.onTrack) of \(summary.judged) on track")
                        .northDisplayNumber(.title)
                        .padding(.vertical, 4)
                }
            }

            if let recovery {
                Section {
                    RecoveryHeadline(recovery: recovery)
                    ForEach(recovery.signals, id: \.key) { signal in
                        NavigationLink(value: MetricRoute(key: signal.key)) { RecoverySignalRow(signal: signal) }
                    }
                } header: {
                    Text("Recovery Today")
                } footer: {
                    Text("HRV, resting heart rate and last night's sleep, each against your last four weeks.")
                }
            }

            if !summary.scores.isEmpty {
                Section("Areas") {
                    NavigationLink(value: AreasRoute()) {
                        Label("By Week", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    ForEach(summary.scores, id: \.key) { score in
                        if let domain = InsightsDomain(rawValue: score.key) {
                            NavigationLink(value: domain) { ScoreRow(score: score) }
                        } else {
                            ScoreRow(score: score)
                        }
                    }
                }
            }

            if !summary.pinned.isEmpty {
                Section("Worth Watching") {
                    ForEach(summary.pinned, id: \.label) { pinned in
                        if let key = pinned.metricKey {
                            NavigationLink(value: MetricRoute(key: key)) { PinnedRow(pinned: pinned) }
                        } else {
                            PinnedRow(pinned: pinned)
                        }
                    }
                }
            }

            Section {
                if health.isEmpty {
                    Text("Nothing from Apple Health in the last two weeks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(health, id: \.key) { metric in
                    NavigationLink(value: MetricRoute(key: metric.key)) { HealthRow(metric: metric) }
                }
            } header: {
                Text("Health")
            } footer: {
                Text("From Apple Health, against your own last four weeks. Connect it in Settings → Connections.")
            }

            if !summary.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(summary.highlights, id: \.self) { Text($0).font(.subheadline) }
                }
            }

            Section("More") {
                NavigationLink(value: ConsistencyRoute()) {
                    Label("Consistency", systemImage: "calendar")
                }
                ForEach([InsightsDomain.sleep, .cardio, .patterns, .timeline, .coach, .spend]) { domain in
                    NavigationLink(value: domain) {
                        Label(domain.title, systemImage: domain.systemImage)
                    }
                }
            }
        }
    }
}

/// One area's score: a ring, the verdict, and why.
private struct ScoreRow: View {
    let score: Components.Schemas.InsightsSummary.ScoresPayloadPayload

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 3)
                if score.hasData {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(score.points, 0), 100)) / 100)
                        .stroke(NorthColor.signal, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(score.hasData ? "\(score.points)" : "–")
                    .font(.subheadline.monospacedDigit())
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(score.label).font(.headline)
                    if score.hasData {
                        Text(score.verdict)
                            .northEyebrow()
                    }
                }
                Text(score.hasData ? score.reason : "Not enough logged to judge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(score.hasData ? "\(score.label), \(score.points) of 100, \(score.verdict). \(score.reason)" : "\(score.label), not enough data")
    }
}

/// A headline number with its shape over the window.
private struct PinnedRow: View {
    let pinned: Components.Schemas.InsightsSummary.PinnedPayloadPayload

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pinned.label)
                    .northEyebrow()
                Text(pinned.value)
                    .northDisplayNumber(.title)
                HStack(spacing: 4) {
                    if pinned.delta.hasPrior {
                        DeltaText(direction: pinned.delta.direction, pct: pinned.delta.pct)
                    }
                    Text(pinned.note).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
            if let chart = pinned.chart {
                Sparkline(chart: chart)
                    .frame(width: 96, height: 40)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// One health metric: its latest day, where that sits against the person's
/// usual, and the last fortnight as a line.
private struct HealthRow: View {
    let metric: InsightsHealthMetric

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(metric.label, systemImage: HealthSymbol.name(for: metric.key))
                    .font(.subheadline)
                Text(metric.latest)
                    .northDisplayNumber(.title3)
                if let usual = metric.usual {
                    UsualChip(state: usual.state)
                }
            }
            Spacer(minLength: 0)
            if metric.recent.count > 1 {
                ValuesSparkline(values: metric.recent)
                    .frame(width: 96, height: 36)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }
}

/// "Above your usual" and friends, quiet when usual. The state is an open
/// string, so anything this build does not know reads as nothing at all.
struct UsualChip: View {
    let state: String

    var body: some View {
        switch state {
        case "above":
            Label("Above your usual", systemImage: "arrow.up").chipStyle()
        case "below":
            Label("Below your usual", systemImage: "arrow.down").chipStyle()
        case "usual":
            Text("Within your usual").font(.caption).foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

private extension Label where Title == Text, Icon == Image {
    func chipStyle() -> some View {
        labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium))
            .foregroundStyle(NorthColor.signal)
    }
}

/// SF Symbols for the health keys this build knows. A key added on the
/// server later still gets a row, with the generic heart.
enum HealthSymbol {
    static func name(for key: String) -> String {
        switch key {
        case "steps": "figure.walk"
        case "active-energy": "flame"
        case "exercise-minutes": "figure.run"
        case "stand-hours": "figure.stand"
        case "daylight": "sun.max"
        case "resting-heart-rate": "heart"
        case "hrv": "waveform.path.ecg"
        case "vo2max": "lungs"
        case "weight": "scalemass"
        case "sleep": "bed.double"
        default: "heart.text.square"
        }
    }
}

struct DeltaText: View {
    let direction: Int
    let pct: Double

    var body: some View {
        Label {
            Text(pct.formatted(.number.precision(.fractionLength(0))) + "%")
        } icon: {
            Image(systemName: direction > 0 ? "arrow.up" : direction < 0 ? "arrow.down" : "equal")
        }
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
    }
}

/// The first series of a chart as a quiet line.
struct Sparkline: View {
    let chart: InsightsChart

    var body: some View {
        ValuesSparkline(values: chart.series.first?.values ?? [])
    }
}

/// A run of values as a quiet line.
struct ValuesSparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            LineMark(x: .value("Day", index), y: .value("Value", value))
                .interpolationMethod(.monotone)
                .foregroundStyle(NorthColor.signal)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
