import AppIntents
import CoreSpotlight
import Foundation
import NorthAPI
import OSLog

/// Keeps Spotlight's copy of the exercise library and the active goals.
///
/// Refreshed after sign-in and whenever the app comes forward, cleared on
/// sign-out: a goal is the account's own, and must not stay searchable on a
/// phone somebody else signs into.
enum SpotlightIndex {
    private static let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "spotlight")

    /// The server answers at most 100 exercises a page.
    private static let pageSize = 100
    /// Past the whole catalog; a runaway page count stops here.
    private static let maxExercises = 2000

    static func refresh() async {
        do {
            let exercises = try await allExercises()
            let goals = try await GoalsService().goals().goals.filter { $0.status == .active }.map(GoalEntity.init)
            let index = CSSearchableIndex.default()
            // Replace rather than add: a goal closed or deleted since the last
            // refresh must stop showing up.
            try await index.deleteAppEntities(ofType: GoalEntity.self)
            try await index.indexAppEntities(exercises)
            try await index.indexAppEntities(goals)
        } catch {
            log.error("spotlight refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func clear() async {
        do {
            try await CSSearchableIndex.default().deleteAllSearchableItems()
        } catch {
            log.error("spotlight clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func allExercises() async throws -> [ExerciseEntity] {
        var found: [ExerciseEntity] = []
        var offset = 0
        while offset < maxExercises {
            let page = try await TrainingService().exercisePage(offset: offset, limit: pageSize)
            found += page.exercises.map(ExerciseEntity.init)
            offset += page.exercises.count
            if page.exercises.isEmpty || offset >= page.total { break }
        }
        return found
    }
}
