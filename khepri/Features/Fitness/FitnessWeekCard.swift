import Charts
import NorthKit
import SwiftUI

/// This week: steps, active minutes and distance over one bar per day. Days
/// with a workout are warm; today is marked under its bar.
struct FitnessWeekCard: View {
    let week: FitnessWeek
    /// Today shows a lighter version that links on to Fitness.
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 16 : 20) {
            if compact {
                NorthCardHeader("This week") {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            } else {
                NorthCardHeader("This week")
            }

            HStack(alignment: .top, spacing: 0) {
                Stat(value: FitnessFormat.compact(week.steps), caption: "steps",
                     detail: week.stepsPerDay > 0 ? "\(FitnessFormat.compact(week.stepsPerDay)) / day" : nil,
                     compact: compact)
                Divider().frame(height: compact ? 36 : 48).padding(.top, 8)
                Stat(value: week.exerciseMinutes.formatted(.number.precision(.fractionLength(0))),
                     caption: "min active", compact: compact)
                Divider().frame(height: compact ? 36 : 48).padding(.top, 8)
                Stat(value: week.distanceKm.formatted(.number.precision(.fractionLength(1))),
                     caption: "km", compact: compact)
            }

            WeekBars(days: week.days, height: compact ? 56 : 96)
        }
        .northSurfaceCard()
    }
}

private struct Stat: View {
    let value: String
    let caption: String
    var detail: String?
    let compact: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.north(compact ? .title2 : .title).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let detail, !compact {
                Text(detail)
                    .font(.north(.subheadline))
                    .foregroundStyle(.tertiary)
            }
            Text(caption)
                .font(.north(compact ? .footnote : .subheadline))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One rounded bar per day, the weekday under it.
private struct WeekBars: View {
    let days: [FitnessWeek.Day]
    let height: CGFloat

    private var peak: Double { max(days.map(\.steps).max() ?? 0, 1) }

    var body: some View {
        VStack(spacing: 8) {
            Chart(days) { day in
                if day.steps > 0 {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                        .foregroundStyle(day.active ? AnyShapeStyle(NorthColor.ember) : AnyShapeStyle(Color(.systemGray3)))
                        .clipShape(.rect(cornerRadius: 4))
                } else {
                    // A thin track keeps empty and future days in the row.
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", peak * 0.04))
                        .foregroundStyle(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 3))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...peak)
            .frame(height: height)

            HStack(spacing: 0) {
                ForEach(days) { day in
                    VStack(spacing: 4) {
                        Text(day.label)
                            .font(.north(.caption).weight(day.isToday ? .semibold : .regular))
                            .foregroundStyle(day.isToday ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        Circle()
                            .fill(day.isToday ? NorthColor.ember : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        days.filter { !$0.isFuture }
            .map { "\($0.label) \(FitnessFormat.compact($0.steps)) steps\($0.active ? ", workout" : "")" }
            .joined(separator: "; ")
    }
}
