import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// Opens one activity type from the cardio page.
struct CardioKindRoute: Hashable {
    let name: String
}

/// One activity type over the last year: how much, how fast and whether it
/// is getting faster, how hard the heart works for it, bests, and when it
/// usually happens.
struct ActivityKindPage: View {
    let name: String
    var service: StatsServicing = StatsService()

    @State private var kind: StatsCardioKind?
    @State private var error: String?

    var body: some View {
        Group {
            if let kind {
                content(kind)
            } else if let error {
                ContentUnavailableView("This did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                kind = try await service.cardioKind(name: name)
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func content(_ kind: StatsCardioKind) -> some View {
        List {
            if kind.sessions == 0 {
                ContentUnavailableView("Nothing this year", systemImage: "figure.run",
                                       description: Text("No \(name.lowercased()) in the last twelve months."))
            } else {
                Section {
                    KindTotals(kind: kind)
                } footer: {
                    Text("The last twelve months.")
                }
                if kind.monthly.count > 1 {
                    Section {
                        RateTrend(kind: kind)
                            .frame(height: 180)
                            .padding(.vertical, 8)
                    } header: {
                        Text(kind.measure == "speed" ? "Speed by Month" : "Pace by Month")
                    } footer: {
                        Text(kind.measure == "speed" ? "Higher is faster." : "Higher on the chart is faster.")
                    }
                }
                if kind.efficiency.count > 1 {
                    Section {
                        EfficiencyTrend(points: kind.efficiency)
                            .frame(height: 160)
                            .padding(.vertical, 8)
                    } header: {
                        Text("Distance per Heartbeat")
                    } footer: {
                        Text("Metres covered for each beat of your heart. Rising means the same effort carries you further: fitter, whatever the pace.")
                    }
                }
                if !kind.bests.isEmpty {
                    Section("Bests") {
                        ForEach(kind.bests, id: \.key) { best in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(best.label)
                                    Text(StatsFormat.shortDate(best.date)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Self.format(best)).font(.body.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let habit = Self.habit(kind) {
                    Section("Habit") {
                        Text(habit)
                    }
                }
            }
        }
    }

    static func format(_ best: Components.Schemas.StatsBest) -> String {
        switch best.unit {
        case "s": StatsFormat.duration(best.value)
        case "km": String(format: "%.1f km", best.value)
        case "km/h": StatsFormat.speed(best.value)
        case "m": String(format: "%.0f m", best.value)
        case "min": StatsFormat.hm(Int(best.value))
        default: best.value.formatted()
        }
    }

    /// "Usually Tuesdays, around 7:00", once there are enough sessions.
    static func habit(_ kind: StatsCardioKind) -> String? {
        guard !kind.usualDay.isEmpty else { return nil }
        var line = "Usually \(kind.usualDay)s"
        if kind.usualHour >= 0 {
            line += String(format: ", around %d:00", kind.usualHour)
        }
        return line + "."
    }
}

private struct KindTotals: View {
    let kind: StatsCardioKind

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                stat("Sessions", "\(kind.sessions)")
                stat("Time", StatsFormat.hm(kind.minutes))
            }
            if kind.distanceKm > 0 {
                GridRow {
                    stat("Distance", String(format: "%.1f km", kind.distanceKm))
                    stat(kind.measure == "speed" ? "Avg Speed" : "Avg Pace",
                         StatsFormat.rate(measure: kind.measure, pace: kind.avgPaceSeconds, speed: kind.avgSpeedKmh) ?? "–")
                }
            }
            if kind.avgHeartRate > 0 || kind.elevationM > 0 {
                GridRow {
                    stat("Avg Heart Rate", kind.avgHeartRate > 0 ? String(format: "%.0f bpm", kind.avgHeartRate) : "–")
                    stat("Climbed", kind.elevationM > 0 ? String(format: "%.0f m", kind.elevationM) : "–")
                }
            }
            // Only a mix is worth a row: indoor runs and rides are their
            // own activity types, so most types are all one or the other.
            if kind.indoor > 0 && kind.outdoor > 0 {
                GridRow {
                    stat("Outdoors", "\(kind.outdoor)")
                    stat("Indoors", "\(kind.indoor)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pace or speed by month. Pace is drawn on a reversed axis so that up is
/// faster on both, and a line going up always reads as getting quicker.
private struct RateTrend: View {
    let kind: StatsCardioKind

    var body: some View {
        let speed = kind.measure == "speed"
        Chart(kind.monthly, id: \.date) { month in
            LineMark(x: .value("Month", StatsFormat.shortMonth(month.date)), y: .value(speed ? "km/h" : "s/km", month.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(NorthColor.Day.move)
            PointMark(x: .value("Month", StatsFormat.shortMonth(month.date)), y: .value(speed ? "km/h" : "s/km", month.value))
                .foregroundStyle(NorthColor.Day.move)
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: !speed))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(speed ? String(format: "%.0f", v) : StatsFormat.pace(v).replacingOccurrences(of: " /km", with: ""))
                    }
                }
            }
        }
    }
}

private struct EfficiencyTrend: View {
    let points: [Components.Schemas.StatsDayValue]

    var body: some View {
        Chart(points, id: \.date) { month in
            LineMark(x: .value("Month", StatsFormat.shortMonth(month.date)), y: .value("m per beat", month.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(NorthColor.signal)
            PointMark(x: .value("Month", StatsFormat.shortMonth(month.date)), y: .value("m per beat", month.value))
                .foregroundStyle(NorthColor.signal)
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}
