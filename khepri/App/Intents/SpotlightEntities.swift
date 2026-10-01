import AppIntents
import CoreSpotlight
import Foundation
import NorthAPI

// Exercises and goals, as things Spotlight can find and Siri can name.
//
// Both open through a khepri:// link, like the other intents, so a tap in
// Spotlight lands by the same router rules as a notification or a widget.

struct ExerciseEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Exercise"
    static let defaultQuery = ExerciseEntityQuery()

    let id: String
    let name: String
    let muscles: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(muscles)", image: .init(systemName: "figure.strengthtraining.traditional"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = name
        attributes.contentDescription = muscles
        attributes.keywords = [name] + muscles.components(separatedBy: ", ")
        return attributes
    }

    init(slug: String, name: String, primaryMuscles: [String]) {
        id = slug
        self.name = name
        muscles = primaryMuscles.map(\.capitalized).joined(separator: ", ")
    }

    init(_ exercise: ExerciseSummary) {
        self.init(slug: exercise.slug, name: exercise.name, primaryMuscles: exercise.primaryMuscles)
    }
}

struct ExerciseEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExerciseEntity] {
        var found: [ExerciseEntity] = []
        for slug in identifiers {
            let exercise = try await NorthAPI.call { try await API.shared.getExercise(path: .init(slug: slug)).ok.body.json }
            found.append(ExerciseEntity(slug: exercise.slug, name: exercise.name, primaryMuscles: exercise.primaryMuscles))
        }
        return found
    }

    func entities(matching string: String) async throws -> [ExerciseEntity] {
        try await TrainingService().searchExercises(string, muscle: nil).map(ExerciseEntity.init)
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        try await TrainingService().searchExercises("", muscle: nil).prefix(20).map(ExerciseEntity.init)
    }
}

struct GoalEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Goal"
    static let defaultQuery = GoalEntityQuery()

    let id: String
    let title: String
    let detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(detail)", image: .init(systemName: "target"))
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.displayName = title
        attributes.contentDescription = detail
        return attributes
    }

    init(_ goal: GoalSummary) {
        id = goal.id
        title = goal.title
        detail = goal.category.capitalized
    }
}

struct GoalEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [GoalEntity] {
        try await goals().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [GoalEntity] {
        try await goals().filter { $0.title.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [GoalEntity] {
        try await goals()
    }

    private func goals() async throws -> [GoalEntity] {
        try await GoalsService().goals().goals.filter { $0.status == .active }.map(GoalEntity.init)
    }
}

/// What a Spotlight tap on an exercise runs, and what "Show push-up in
/// Khepri" asks for.
struct OpenExerciseIntent: OpenIntent {
    static let title: LocalizedStringResource = "Show Exercise"
    static let description = IntentDescription("Opens an exercise with its steps and form cues.")

    @Parameter(title: "Exercise")
    var target: ExerciseEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "khepri://exercises/\(target.id)")!))
    }
}

struct OpenGoalIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Goal"
    static let description = IntentDescription("Opens one of your goals.")

    @Parameter(title: "Goal")
    var target: GoalEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "khepri://goals/\(target.id)")!))
    }
}
