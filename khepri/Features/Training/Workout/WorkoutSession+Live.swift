import Foundation
import NorthAPI
import NorthKit

extension WorkoutSession {
    /// A workout with the real server, Live Activity, Health, snapshot and
    /// notifications behind it.
    static func live(title: String, day: TrainingDay, planWeekday: String) -> WorkoutSession {
        WorkoutSession(
            title: title,
            day: day,
            planWeekday: planWeekday,
            service: ActivityService(),
            live: WorkoutLiveActivityController(),
            health: HealthWorkoutWriter(),
            lifts: LiftService(),
            snapshots: WorkoutSnapshotStore(),
            restNotifications: RestNotifications()
        )
    }

    /// The workout the app was killed during, ready to pick up again; nil
    /// when there is none, or it is unreadable or too old.
    static func resumingKilledWorkout() -> WorkoutSession? {
        let store = WorkoutSnapshotStore()
        guard let snapshot = store.load() else { return nil }
        return WorkoutSession(
            restoring: snapshot,
            service: ActivityService(),
            live: WorkoutLiveActivityController(),
            health: HealthWorkoutWriter(),
            lifts: LiftService(),
            snapshots: store,
            restNotifications: RestNotifications()
        )
    }

    /// Where the workout is, as the Lock Screen and Dynamic Island show it.
    var liveState: WorkoutLiveState {
        let currentPhase: WorkoutActivityAttributes.ContentState.Phase
        if phase == .finished {
            currentPhase = .finished
        } else if isPaused {
            currentPhase = .paused
        } else if restEndsAt != nil {
            currentPhase = .resting
        } else {
            currentPhase = .working
        }

        return WorkoutLiveState(
            exerciseName: current?.name ?? title,
            setNumber: setNumber,
            totalSets: current?.sets ?? 0,
            phase: currentPhase,
            restEndsAt: restEndsAt,
            exerciseNumber: min(exerciseIndex + 1, exercises.count),
            totalExercises: exercises.count,
            movingSince: movingSince,
            finalDuration: phase == .finished ? movingTime : nil
        )
    }
}
