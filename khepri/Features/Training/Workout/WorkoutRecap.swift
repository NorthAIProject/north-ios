import Charts
import NorthAPI
import NorthKit
import SwiftUI

typealias LiftRecap = Components.Schemas.LiftRecap

/// A finished workout in a sentence and per exercise, computed by the server
/// from the session and its sets — the same recap the web plan page, Insights
/// and the coach read.
protocol RecapServicing: Sendable {
    func recap(sessionID: String) async throws -> LiftRecap
}

struct RecapService: RecapServicing {
    var api: Client = API.shared

    func recap(sessionID: String) async throws -> LiftRecap {
        try await NorthAPI.call { try await api.getWorkoutRecap(path: .init(sessionID: sessionID)).ok.body.json }
    }
}

/// What the recap views draw: a sentence, each exercise against last time,
/// and the volume bars. Built from the server's recap, or from the workout
/// on the phone when the server cannot be reached, so the finish screen
/// still says something useful offline.
struct WorkoutRecapModel: Equatable {
    struct Bar: Identifiable, Equatable {
        let exercise: String
        let series: Series
        let kg: Double
        var id: String { exercise + series.rawValue }
    }

    /// One movement: the best set, the estimated max, and how that max moved.
    struct Exercise: Identifiable, Equatable {
        let name: String
        let sets: Int
        /// Heaviest set by estimated max. Nil for a bodyweight movement.
        let bestWeightKg: Double?
        let bestReps: Int
        let e1rmKg: Double
        /// Nil the first time this movement is logged.
        let changeKg: Double?
        let volumeKg: Double
        let previousVolumeKg: Double?
        var id: String { name }
    }

    enum Series: String, Plottable {
        case now = "This session"
        case before = "Last time"
    }

    var sentence: String
    var exercises: [Exercise]

    /// Bars in paint order. The two series share a column: the taller one is
    /// drawn first, behind, and the shorter one covers it. A side-by-side
    /// pair would halve every column and run the names together.
    var bars: [Bar] {
        exercises.flatMap { exercise -> [Bar] in
            let now = Bar(exercise: exercise.name, series: .now, kg: exercise.volumeKg)
            guard let beforeKg = exercise.previousVolumeKg else { return [now] }
            let before = Bar(exercise: exercise.name, series: .before, kg: beforeKg)
            return beforeKg >= exercise.volumeKg ? [before, now] : [now, before]
        }
    }

    var hasComparison: Bool { exercises.contains { $0.previousVolumeKg != nil } }
    var hasVolume: Bool { exercises.contains { $0.volumeKg > 0 } }

    init(sentence: String, exercises: [Exercise]) {
        self.sentence = sentence
        self.exercises = exercises
    }

    init(_ recap: LiftRecap) {
        sentence = recap.sentence
        exercises = recap.exercises.map { row in
            let parsed = row.best.flatMap(Self.parseBest)
            return Exercise(name: row.name, sets: row.sets, bestWeightKg: parsed?.kg, bestReps: parsed?.reps ?? 0,
                            e1rmKg: row.e1rmKg, changeKg: row.changeE1rmKg, volumeKg: row.volumeKg,
                            previousVolumeKg: row.previousVolumeKg)
        }
    }

    /// The recap from what the phone saw: the sets logged and the last
    /// workout's sets it loaded at the start.
    @MainActor
    static func local(from session: WorkoutSession) -> WorkoutRecapModel {
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [WorkoutSession.LoggedSet]] = [:]
        for set in session.logged {
            if grouped[set.exerciseKey] == nil { order.append(set.exerciseKey) }
            names[set.exerciseKey] = set.exerciseName
            grouped[set.exerciseKey, default: []].append(set)
        }
        let exercises = order.map { key in
            let sets = grouped[key] ?? []
            let name = names[key] ?? key
            let volume = sets.reduce(0) { $0 + $1.volumeKg }
            let best = sets.filter { $0.weightKg > 0 }.max { $0.e1rmKg < $1.e1rmKg }
            var previous: Double?
            var change: Double?
            if let last = session.lastTime[key], !last.isEmpty {
                previous = last.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
                if let best, let prevMax = last.map(\.e1rmKg).max(), prevMax > 0 {
                    change = best.e1rmKg - prevMax
                }
            }
            return Exercise(name: name, sets: sets.count, bestWeightKg: best?.weightKg, bestReps: best?.reps ?? 0,
                            e1rmKg: best?.e1rmKg ?? 0, changeKg: change, volumeKg: volume, previousVolumeKg: previous)
        }
        return WorkoutRecapModel(sentence: localSentence(session), exercises: exercises)
    }

    /// A name short enough to live in its own column. The full name is in
    /// the exercise list; the axis only has to tell the columns apart.
    nonisolated static func axisLabel(_ name: String, among count: Int) -> String {
        let budget = max(1, 28 / max(count, 1))
        if name.count <= budget { return name }
        if budget == 1 { return "…" }
        return String(name.prefix(budget - 1)) + "…"
    }

    /// The server's best set is "105 kg × 5". The view reformats the numbers
    /// into the person's units, so the string has to come apart.
    nonisolated static func parseBest(_ best: String) -> (kg: Double, reps: Int)? {
        let parts = best.components(separatedBy: " × ")
        guard parts.count == 2, let reps = Int(parts[1]) else { return nil }
        let number = parts[0].replacingOccurrences(of: " kg", with: "")
        guard let kg = Double(number), reps > 0 else { return nil }
        return (kg, reps)
    }

    @MainActor
    private static func localSentence(_ session: WorkoutSession) -> String {
        var parts: [String] = []
        let minutes = Int((session.movingTime / 60).rounded())
        if minutes >= 1 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if session.completedSets > 0 {
            parts.append(session.totalSets > 0
                ? "\(session.completedSets) of \(session.totalSets) sets"
                : "\(session.completedSets) sets")
        }
        if session.volumeKg > 0 {
            parts.append(session.volumeKg.formatted(.number.precision(.fractionLength(0))) + " kg")
        }
        return parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
    }
}

/// This session's volume per exercise, drawn over last time's when there was one.
struct WorkoutRecapChart: View {
    let model: WorkoutRecapModel

    var body: some View {
        let count = model.exercises.count
        Chart(model.bars) { bar in
            BarMark(
                x: .value("Exercise", bar.exercise),
                y: .value("Volume (kg)", bar.kg)
            )
            .foregroundStyle(by: .value("When", bar.series))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            WorkoutRecapModel.Series.now: NorthColor.signal,
            WorkoutRecapModel.Series.before: Color.secondary.opacity(0.35)
        ])
        .chartLegend(model.hasComparison ? .visible : .hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(WorkoutRecapModel.axisLabel(name, among: count))
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Volume per exercise, this session against last time")
    }
}

/// The recap under the finish screen's numbers: the sentence, the bars, then
/// each exercise's best set and how its estimated max moved.
struct WorkoutRecapCard: View {
    let model: WorkoutRecapModel
    var imperial = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.sentence.isEmpty {
                Text(model.sentence)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.hasVolume {
                WorkoutRecapChart(model: model)
            }
            if !model.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.exercises) { exercise in
                        exerciseRow(exercise)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private func exerciseRow(_ exercise: WorkoutRecapModel.Exercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(exercise.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if let best = bestText(exercise) {
                    Text(best)
                } else if exercise.sets > 0 {
                    Text("\(exercise.sets) sets")
                }
                HStack(spacing: 4) {
                    if exercise.e1rmKg > 0 {
                        Text("est. \(weight(exercise.e1rmKg))")
                    }
                    if let change = exercise.changeKg, abs(change) >= 0.05 {
                        Text(changeText(change))
                            .foregroundStyle(change > 0 ? AnyShapeStyle(NorthColor.signal) : AnyShapeStyle(.secondary))
                    }
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func bestText(_ exercise: WorkoutRecapModel.Exercise) -> String? {
        guard let kg = exercise.bestWeightKg, exercise.bestReps > 0 else { return nil }
        return "\(weight(kg)) × \(exercise.bestReps)"
    }

    private func changeText(_ change: Double) -> String {
        let sign = change > 0 ? "+" : "−"
        return sign + weight(abs(change))
    }

    private func weight(_ kg: Double) -> String {
        let shown = LiftMath.display(kg, imperial: imperial)
        let digits: Int = shown == shown.rounded() ? 0 : 1
        return shown.formatted(.number.precision(.fractionLength(digits))) + (imperial ? " lb" : " kg")
    }
}
