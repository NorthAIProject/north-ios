import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// The web Overview's trend cards: a headline number and a sparkline each,
/// then recent fasts against their targets.
struct TrendsSection: View {
    let trends: DayTrends

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trends").northEyebrow()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(trends.series, id: \.key) { TrendCard(trend: $0) }
            }
            if !trends.fasts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent fasts").font(.caption.weight(.semibold)).foregroundStyle(NorthColor.Day.fat)
                    ForEach(Array(trends.fasts.enumerated()), id: \.offset) { _, fast in
                        HStack {
                            Text(fast.startedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Gauge(value: min(fast.hours / Double(max(fast.targetHours, 1)), 1)) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .tint(NorthColor.Day.fat)
                            Text("\(fast.hours, format: .number.precision(.fractionLength(1)))h")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(fast.met ? NorthColor.Day.food : .secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(12)
                .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large))
            }
        }
    }
}

private struct TrendCard: View {
    let trend: DayTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
                Spacer()
                Text(meta).font(.caption2).foregroundStyle(.secondary)
            }
            (Text(trend.headline, format: .number.precision(.fractionLength(decimals)))
                + Text(" \(trend.unit)").font(.caption).foregroundStyle(.secondary))
                .font(.title3.weight(.semibold).monospacedDigit())
            Chart(Array(trend.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.at), y: .value("Value", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(color)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 36)
        }
        .padding(12)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large))
    }

    private var title: LocalizedStringKey {
        switch trend.key {
        case .weight: "Weight"
        case .systolic: "Systolic"
        case .activeEnergy: "Energy"
        case .sleep: "Sleep"
        case .caffeine: "Caffeine"
        }
    }

    private var color: Color {
        switch trend.key {
        case .weight: NorthColor.Day.stand
        case .systolic: NorthColor.Day.move
        case .activeEnergy: NorthColor.Day.exercise
        case .sleep: NorthColor.Day.sleep
        case .caffeine: NorthColor.Day.caffeine
        }
    }

    private var decimals: Int { trend.key == .weight || trend.key == .sleep ? 1 : 0 }

    private var meta: String {
        switch trend.key {
        case .weight, .systolic: String(localized: "\(trend.count) readings")
        default: String(localized: "\(trend.windowDays) days")
        }
    }
}
