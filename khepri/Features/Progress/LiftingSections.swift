import Charts
import NorthAPI
import NorthKit
import SwiftUI

/// Lifting for the window the Progress tab shows: volume, records, each
/// exercise's best and estimated max, and sets per muscle. Loads on its own
/// so the rest of Training shows even when this fails.
struct LiftingSections: View {
    let range: String
    var service: LiftServicing = LiftService()

    @State private var stats: LiftStats?
    @State private var failed = false
    @State private var imperial = false

    var body: some View {
        Group {
            if let stats {
                if stats.sets == 0 {
                    Section("Lifting") {
                        Text("No sets logged in this window. Enter the weight of each set during a workout and it shows up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    content(stats)
                }
            } else if failed {
                Section("Lifting") {
                    Text("Lifting stats did not load.").foregroundStyle(.secondary)
                }
            } else {
                Section("Lifting") { ProgressView() }
            }
        }
        .task(id: range) {
            imperial = (try? await SettingsService().preferences().unitsSystem) == .imperial
            do {
                stats = try await service.stats(range: range)
                failed = false
            } catch {
                failed = stats == nil
            }
        }
    }

    private func weight(_ kg: Double) -> String {
        "\(LiftMath.display(kg, imperial: imperial).formatted(.number.precision(.fractionLength(0...1)))) \(imperial ? "lb" : "kg")"
    }

    @ViewBuilder
    private func content(_ stats: LiftStats) -> some View {
        Section("Lifting") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    stat("Volume", weight(stats.volumeKg))
                    stat("Sets", "\(stats.sets)")
                }
                GridRow {
                    stat("Workouts", "\(stats.workouts)")
                    stat("Reps", "\(stats.reps)")
                }
            }
            .padding(.vertical, 4)
            if stats.priorVolumeKg > 0 {
                let pct = (stats.volumeKg - stats.priorVolumeKg) / stats.priorVolumeKg * 100
                Text("\(pct >= 0 ? "Up" : "Down") \(abs(pct).formatted(.number.precision(.fractionLength(0))))% in volume on the window before")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if !stats.records.isEmpty {
            Section("Records") {
                ForEach(Array(stats.records.enumerated()), id: \.offset) { _, record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.exerciseName)
                            Text("\(weight(record.weightKg)) × \(record.reps) · \(record.date)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(weight(record.e1rmKg - record.previousE1rmKg))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(NorthColor.signal)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }

        if stats.weekly.count > 1 {
            Section("Weekly Volume") {
                Chart(stats.weekly, id: \.date) { week in
                    BarMark(x: .value("Week", String(week.date.suffix(5))),
                            y: .value("Volume", LiftMath.display(week.value, imperial: imperial)))
                        .foregroundStyle(NorthColor.signal)
                }
                .frame(height: 160)
                .padding(.vertical, 8)
            }
        }

        Section("Exercises") {
            ForEach(stats.exercises, id: \.key) { exercise in
                NavigationLink {
                    LiftExerciseDetail(exercise: exercise, imperial: imperial)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            Text("\(exercise.sets) sets · best \(weight(exercise.bestWeightKg))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(weight(exercise.bestE1rmKg)).font(.subheadline.monospacedDigit())
                            Text("est. 1RM").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !stats.muscles.isEmpty {
            let most = stats.muscles.map(\.sets).max() ?? 1
            Section("Sets per Muscle") {
                ForEach(stats.muscles, id: \.muscle) { muscle in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(muscle.muscle.replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text("\(muscle.sets)").monospacedDigit().foregroundStyle(.secondary)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(NorthColor.signal)
                                .frame(width: proxy.size.width * CGFloat(muscle.sets) / CGFloat(most))
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).northEyebrow()
            Text(value).northDisplayNumber(.title2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One exercise over the window: its estimated max day by day.
struct LiftExerciseDetail: View {
    let exercise: Components.Schemas.LiftExerciseStats
    let imperial: Bool

    private func weight(_ kg: Double) -> String {
        "\(LiftMath.display(kg, imperial: imperial).formatted(.number.precision(.fractionLength(0...1)))) \(imperial ? "lb" : "kg")"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Estimated 1RM", value: weight(exercise.bestE1rmKg))
                LabeledContent("Heaviest set", value: weight(exercise.bestWeightKg))
                LabeledContent("Sets", value: "\(exercise.sets)")
                LabeledContent("Reps", value: "\(exercise.reps)")
                LabeledContent("Volume", value: weight(exercise.volumeKg))
                LabeledContent("Last trained", value: exercise.lastOn)
            }
            if exercise.trend.count > 1 {
                Section {
                    Chart(exercise.trend, id: \.date) { point in
                        LineMark(x: .value("Day", String(point.date.suffix(5))),
                                 y: .value("Est. 1RM", LiftMath.display(point.value, imperial: imperial)))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(NorthColor.signal)
                        PointMark(x: .value("Day", String(point.date.suffix(5))),
                                  y: .value("Est. 1RM", LiftMath.display(point.value, imperial: imperial)))
                            .foregroundStyle(NorthColor.signal)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .padding(.vertical, 8)
                } header: {
                    Text("Estimated 1RM")
                } footer: {
                    Text("The best set of each day, by Epley's formula: weight × (1 + reps ÷ 30).")
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
