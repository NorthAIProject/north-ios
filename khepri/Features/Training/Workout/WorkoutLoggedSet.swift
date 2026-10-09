import Foundation
import NorthAPI

extension WorkoutSession {
    /// One set as it was done.
    struct LoggedSet: Equatable, Codable, Identifiable {
        var id = UUID()
        let exerciseKey: String
        let exerciseName: String
        var exerciseSlug: String?
        let setNumber: Int
        let weightKg: Double
        let reps: Int
        var kind: SetKind = .work
        /// Reps in reserve; nil when not said.
        var rir: Int?
        var performedAt: Date
        var upload: SetUpload = .pending

        var counts: Bool { kind.counts }
        /// Weight times reps. A warm-up has none, as on the server.
        var volumeKg: Double { counts ? weightKg * Double(reps) : 0 }
        var e1rmKg: Double { LiftMath.e1rm(weightKg: weightKg, reps: reps) }

        var serverID: String? { if case .saved(let id) = upload { id } else { nil } }

        /// What `POST /lifts/sets` is sent for the set. A work set says so,
        /// which is also what the server assumes when it is left out; reps in
        /// reserve are sent only when given.
        func input(activitySessionID: String?) -> Components.Schemas.LiftSetInput {
            Components.Schemas.LiftSetInput(
                exerciseName: exerciseName, exerciseSlug: exerciseSlug, setNumber: setNumber,
                weightKg: weightKg, reps: reps, performedAt: performedAt, activitySessionId: activitySessionID,
                kind: kind.payload, rir: rir)
        }
    }
}

/// Whether the server has a set.
enum SetUpload: Equatable, Codable {
    /// Not answered yet, or the app was killed before it was.
    case pending
    case saved(id: String)
    case failed
}
