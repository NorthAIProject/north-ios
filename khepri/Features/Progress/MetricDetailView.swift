import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// One metric over the window: the number, its shape, and how it compares
/// with the window before.
struct MetricDetailView: View {
    let key: String
    let range: String
    let service: InsightsServicing

    @State private var metric: InsightMetric?
    @State private var error: String?

    var body: some View {
        Group {
            if let metric {
                content(metric)
            } else if let error {
                ContentUnavailableView("This did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(metric?.label ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) {
            do {
                metric = try await service.metric(key, range: range)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func content(_ metric: InsightMetric) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.range.label)
                        .northEyebrow()
                    Text(metric.headline)
                        .northDisplayNumber(.largeTitle)
                    if metric.trend.hasPrior {
                        Text(metric.trend.word)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !metric.note.isEmpty {
                        Text(metric.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if metric.hasData {
                Section {
                    MetricChart(chart: metric.chart)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                }
            } else {
                Section {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if metric.comparison.hasPrior {
                Section("Compared With Before") {
                    ComparisonRow(label: metric.comparison.currentLabel, value: metric.comparison.currentValue,
                                  pct: metric.comparison.currentPct, emphasised: true)
                    ComparisonRow(label: metric.comparison.priorLabel, value: metric.comparison.priorValue,
                                  pct: metric.comparison.priorPct, emphasised: false)
                }
            }

            if !metric.highlights.isEmpty {
                Section("Highlights") {
                    ForEach(metric.highlights, id: \.self) { Text($0).font(.subheadline) }
                }
            }
        }
    }

    private var emptyText: String {
        HealthMetric(rawValue: key) != nil
            ? "Nothing from Apple Health for this window. Connect it in Settings → Connections, and allow this kind of data."
            : "Nothing logged for this window."
    }
}

private struct MetricChart: View {
    let chart: InsightsChart

    var body: some View {
        let values = chart.series.first?.values ?? []
        let points = values.enumerated().map { (label: chart.labels.indices.contains($0.offset) ? chart.labels[$0.offset] : "\($0.offset)", value: $0.element) }
        Chart(points, id: \.label) { point in
            BarMark(x: .value("When", point.label), y: .value("Value", point.value))
                .foregroundStyle(NorthColor.signal)
        }
        .chartXAxis {
            // Every label on a thirty-day chart is a smear; a few are enough.
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }
}

private struct ComparisonRow: View {
    let label: String
    let value: String
    let pct: Int
    let emphasised: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(emphasised ? .primary : .secondary)
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(emphasised ? NorthColor.signal : Color(.separator))
                    .frame(width: proxy.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
