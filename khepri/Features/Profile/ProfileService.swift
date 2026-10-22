import Foundation
import NorthAPI

typealias ProfileView = Components.Schemas.ProfileView
typealias ProfileWorkouts = Components.Schemas.ProfileWorkouts
typealias WorkoutCard = Components.Schemas.WorkoutCard
typealias WorkoutExercise = Components.Schemas.WorkoutExercise

protocol ProfileServicing: Sendable {
    /// Somebody's profile, with the sections they share with you.
    func profile(handle: String) async throws -> ProfileView
    /// A page of their finished workouts, newest first. Pass the previous
    /// page's `before` for the next one.
    func workouts(handle: String, before: Date?) async throws -> ProfileWorkouts
    /// One of their workouts with every exercise.
    func workout(handle: String, sessionID: String) async throws -> WorkoutCard
}

struct ProfileService: ProfileServicing {
    var api: Client = API.shared

    func profile(handle: String) async throws -> ProfileView {
        try await NorthAPI.call { try await api.getPublicProfile(path: .init(handle: handle)).ok.body.json }
    }

    func workouts(handle: String, before: Date?) async throws -> ProfileWorkouts {
        try await NorthAPI.call {
            try await api.listProfileWorkouts(path: .init(handle: handle), query: .init(before: before)).ok.body.json
        }
    }

    func workout(handle: String, sessionID: String) async throws -> WorkoutCard {
        try await NorthAPI.call {
            try await api.getProfileWorkout(path: .init(handle: handle, sessionID: sessionID)).ok.body.json
        }
    }
}
