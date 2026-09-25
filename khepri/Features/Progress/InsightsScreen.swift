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
                SummaryList(summary: summary)
            }
        }
    }
}

struct MetricRoute: Hashable {
    let key: String
}

private struct SummaryList: View {
    let summary: InsightsSummary

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

            if !summary.scores.isEmpty {
                Section("Areas") {
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
                ForEach(HealthMetric.allCases) { metric in
                    NavigationLink(value: MetricRoute(key: metric.rawValue)) {
                        Label(metric.label, systemImage: metric.systemImage)
                    }
                }
            } header: {
                Text("Health")
            } footer: {
                Text("From Apple Health. Connect it in Settings → Connections.")
            }

            if !summary.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(summary.highlights, id: \.self) { Text($0).font(.subheadline) }
                }
            }

            Section("More") {
                ForEach([InsightsDomain.timeline, .coach, .spend]) { domain in
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
        let values = chart.series.first?.values ?? []
        Chart(Array(values.enumerated()), id: \.offset) { index, value in
            LineMark(x: .value("Day", index), y: .value("Value", value))
                .interpolationMethod(.monotone)
                .foregroundStyle(NorthColor.signal)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
