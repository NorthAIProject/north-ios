import Foundation
import NorthAPI

/// Where the workout is, what each set starts from, and what the sets add
/// up to: all of it worked out from the session's state.
extension WorkoutSession {
    var current: DayExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }

    var next: DayExercise? {
        guard let current else { return nil }
        if setNumber < current.sets { return current }
        return exercises.indices.contains(exerciseIndex + 1) ? exercises[exerciseIndex + 1] : nil
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    var isLastSet: Bool { exerciseIndex == exercises.count - 1 && setNumber == (current?.sets ?? 0) }

    /// Start moved later by paused time: a timer from here shows moving time.
    var movingSince: Date { (startedAt ?? now()).addingTimeInterval(pausedTotal) }

    var movingTime: TimeInterval {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? now()
        return end.timeIntervalSince(startedAt) - pausedTotal
    }

    var restEndsAt: Date? { if case .resting(let until) = phase { until } else { nil } }

    /// The rest running down now, for the notification at its end; nil while
    /// working or paused.
    var restEnd: RestEnd? {
        guard let restEndsAt, !isPaused, let current else { return nil }
        return RestEnd(endsAt: restEndsAt, exerciseName: current.name, setNumber: setNumber, totalSets: current.sets)
    }

    func key(for exercise: DayExercise) -> String { LiftMath.key(slug: exercise.catalogSlug, name: exercise.name) }

    /// What the set in hand starts from: this workout's previous set of the
    /// exercise, else the same set last time, else last time's final set.
    /// Nil when the exercise has never been done with a weight.
    var suggestedWeightKg: Double? {
        guard let current else { return nil }
        let key = key(for: current)
        if let previous = logged.last(where: { $0.exerciseKey == key }) { return previous.weightKg }
        let last = lastWorkSets(key)
        return (last.first { $0.setNumber == setNumber } ?? last.last)?.weightKg
    }

    /// Reps start from the plan's number, else last time's.
    var suggestedReps: Int {
        guard let current else { return 1 }
        if let planned = LiftMath.reps(from: current.reps) { return planned }
        let last = lastWorkSets(key(for: current))
        return (last.first { $0.setNumber == setNumber } ?? last.last)?.reps ?? 10
    }

    /// The kind of the exercise's previous set: warm-ups usually come in a
    /// row, then work sets. The first set of an exercise is work.
    var suggestedKind: SetKind {
        guard let current else { return .work }
        let key = key(for: current)
        return logged.last { $0.exerciseKey == key }?.kind ?? .work
    }

    /// This workout's sets of the exercise in hand, in order.
    var loggedForCurrent: [LoggedSet] {
        guard let current else { return [] }
        let key = key(for: current)
        return logged.filter { $0.exerciseKey == key }
    }

    /// Last time's warm-ups are not what a work set starts from.
    fileprivate func lastWorkSets(_ key: String) -> [LiftSet] {
        (lastTime[key] ?? []).filter { $0.setKind.counts }
    }

    /// Last time's sets of the exercise in hand, for "last time" under the
    /// weight field.
    var lastTimeForCurrent: [LiftSet] {
        guard let current else { return [] }
        return lastTime[key(for: current)] ?? []
    }

    var volumeKg: Double { logged.reduce(0) { $0 + $1.volumeKg } }

    /// Exercises whose best set today beat every set of the last workout, by
    /// estimated max. Warm-ups never count.
    var improvements: [LoggedSet] {
        var best: [String: LoggedSet] = [:]
        for set in logged where set.weightKg > 0 && set.counts {
            if set.e1rmKg > (best[set.exerciseKey]?.e1rmKg ?? 0) { best[set.exerciseKey] = set }
        }
        return best.values.filter { set in
            let previous = lastWorkSets(set.exerciseKey).map(\.e1rmKg).max() ?? 0
            return previous > 0 && set.e1rmKg > previous + 0.05
        }
        .sorted { $0.exerciseName < $1.exerciseName }
    }
}
