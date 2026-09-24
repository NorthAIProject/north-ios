#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The workout on the Lock Screen and in the Dynamic Island.
///
/// Shared by the app, which starts and updates the activity, and the widget
/// extension, which draws it. It lives in NorthKit because both targets link
/// it and the two must agree on this type exactly.
public struct WorkoutActivityAttributes: ActivityAttributes {
    /// What changes during the workout.
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case working, resting, paused
        }

        public var exerciseName: String
        public var setNumber: Int
        public var totalSets: Int
        public var phase: Phase
        /// When rest ends; the system counts down to it without updates.
        public var restEndsAt: Date?
        /// Exercise position, for "3 of 6".
        public var exerciseNumber: Int
        public var totalExercises: Int
        /// The start, moved later by time spent paused, so a timer counting
        /// up from it shows moving time.
        public var movingSince: Date

        public init(exerciseName: String, setNumber: Int, totalSets: Int, phase: Phase, restEndsAt: Date?,
                    exerciseNumber: Int, totalExercises: Int, movingSince: Date) {
            self.exerciseName = exerciseName
            self.setNumber = setNumber
            self.totalSets = totalSets
            self.phase = phase
            self.restEndsAt = restEndsAt
            self.exerciseNumber = exerciseNumber
            self.totalExercises = totalExercises
            self.movingSince = movingSince
        }
    }

    /// What stays fixed for the workout.
    public var title: String
    public var startedAt: Date

    public init(title: String, startedAt: Date) {
        self.title = title
        self.startedAt = startedAt
    }
}
#endif
