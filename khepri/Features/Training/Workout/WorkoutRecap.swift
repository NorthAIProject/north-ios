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

/// What the recap views draw: a sentence and each exercise's volume beside
/// last time's. Built from the server's recap, or from the workout on the
/// phone when the server cannot be reached, so the finish screen still says
/// something useful offline.
struct WorkoutRecapModel: Equatable {
    struct Bar: Identifiable, Equatable {
        let exercise: String
        let series: Series
        let kg: Double
        var id: String { exercise + series.rawValue }
    }

    enum Series: String, Plottable {
        case now = "This session"
        case before = "Last time"
    }

    var sentence: String
    var bars: [Bar]

    var hasComparison: Bool { bars.contains { $0.series == .before } }
    var hasVolume: Bool { bars.contains { $0.kg > 0 } }

    init(sentence: String, bars: [Bar]) {
        self.sentence = sentence
        self.bars = bars
    }

    init(_ recap: LiftRecap) {
        sentence = recap.sentence
        bars = recap.exercises.flatMap { e -> [Bar] in
            var out = [Bar(exercise: e.name, series: .now, kg: e.volumeKg)]
            if let before = e.previousVolumeKg { out.append(Bar(exercise: e.name, series: .before, kg: before)) }
            return out
        }
    }

    /// The recap from what the phone saw: the sets logged and the last
    /// workout's sets it loaded at the start.
    @MainActor
    static func local(from session: WorkoutSession) -> WorkoutRecapModel {
        var order: [String] = []
        var names: [String: String] = [:]
        var volume: [String: Double] = [:]
        for set in session.logged {
            if volume[set.exerciseKey] == nil { order.append(set.exerciseKey) }
            names[set.exerciseKey] = set.exerciseName
            volume[set.exerciseKey, default: 0] += set.volumeKg
        }
        var bars: [Bar] = []
        for key in order {
            let name = names[key] ?? key
            bars.append(Bar(exercise: name, series: .now, kg: volume[key] ?? 0))
            if let last = session.lastTime[key], !last.isEmpty {
                let before = last.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
                bars.append(Bar(exercise: name, series: .before, kg: before))
            }
        }
        return WorkoutRecapModel(sentence: localSentence(session), bars: bars)
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

/// This session's volume per exercise, beside last time's when there was one.
struct WorkoutRecapChart: View {
    let model: WorkoutRecapModel

    var body: some View {
        Chart(model.bars) { bar in
            BarMark(
                x: .value("Exercise", bar.exercise),
                y: .value("Volume (kg)", bar.kg)
            )
            .foregroundStyle(by: .value("When", bar.series))
            .position(by: .value("When", bar.series))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale([
            WorkoutRecapModel.Series.now: NorthColor.signal,
            WorkoutRecapModel.Series.before: Color.secondary.opacity(0.35),
        ])
        .chartLegend(model.hasComparison ? .visible : .hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel(orientation: .automatic, horizontalSpacing: 2) }
        }
        .frame(height: 180)
        .accessibilityLabel("Volume per exercise, this session against last time")
    }
}

/// The recap under the finish screen's numbers: the sentence, then the bars.
struct WorkoutRecapCard: View {
    let model: WorkoutRecapModel

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
}
