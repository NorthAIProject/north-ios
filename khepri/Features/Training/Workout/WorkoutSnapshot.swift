import Foundation
import NorthAPI

/// A workout in progress, written down after every change so it survives
/// the app being killed: the plan's exercises, where the workout is, every
/// set logged with whether the server has it, and the server and Live
/// Activity sessions to rejoin.
struct WorkoutSnapshot: Codable, Equatable {
    /// Bumped when the shape changes; a snapshot of another version is
    /// thrown away rather than half-read.
    static let currentVersion = 1

    var version = Self.currentVersion
    /// The last change, which is what "too old to resume" is measured from.
    var savedAt: Date
    var title: String
    var planWeekday: String
    /// This week's exercises, already adjusted for the week.
    var exercises: [DayExercise]
    var exerciseIndex: Int
    var setNumber: Int
    var completedSets: Int
    var startedAt: Date
    /// When rest ends, as a wall-clock time; nil while working.
    var restEndsAt: Date?
    var isPaused: Bool
    var pausedAt: Date?
    var pausedTotal: TimeInterval
    /// Rest left when paused mid-rest.
    var restRemaining: TimeInterval?
    /// The server's activity session, when it had answered.
    var recorded: ActivitySession?
    /// The Lock Screen activity to re-attach to.
    var liveActivityID: String?
    var notice: String?
    var logged: [WorkoutSession.LoggedSet]
    var lastTime: [String: [LiftSet]]
}

extension WorkoutSession {
    /// The workout as a relaunch would resume it; nil before it starts and
    /// once it is over.
    var snapshot: WorkoutSnapshot? {
        guard let startedAt, phase != .ready, phase != .finished else { return nil }
        return WorkoutSnapshot(
            savedAt: now(), title: title, planWeekday: planWeekday, exercises: exercises,
            exerciseIndex: exerciseIndex, setNumber: setNumber, completedSets: completedSets, startedAt: startedAt,
            restEndsAt: restEndsAt, isPaused: isPaused, pausedAt: pausedAt, pausedTotal: pausedTotal,
            restRemaining: restRemaining, recorded: recorded, liveActivityID: liveActivityID,
            notice: notice, logged: logged, lastTime: lastTime)
    }
}
