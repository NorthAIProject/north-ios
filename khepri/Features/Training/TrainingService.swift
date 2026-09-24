import Foundation
import NorthAPI

typealias PlanDetail = Components.Schemas.PlanDetail
typealias PlanSummary = Components.Schemas.PlanSummary
typealias TrainingDay = Components.Schemas.TrainingDay
typealias DayExercise = Components.Schemas.DayExercise
typealias TrainingIntake = Components.Schemas.TrainingIntake
typealias ExerciseSummary = Components.Schemas.ExerciseSummary
typealias ActivitySession = Components.Schemas.ActivitySession

/// What an edit produced: the new version, or the newest one when the edit
/// was made against a version someone else had already replaced.
enum PlanEditResult: Equatable {
    case saved(PlanDetail)
    case superseded(PlanDetail)
}

/// Training over the generated client.
protocol TrainingServicing: Sendable {
    func plans() async throws -> [PlanSummary]
    func plan(_ id: String) async throws -> PlanDetail
    func latestIntake() async throws -> TrainingIntake?
    func createPlan(_ intake: TrainingIntake) async throws -> PlanDetail

    func setStartTime(plan: String, day: Int, to time: String?) async throws -> PlanEditResult
    func addExercise(plan: String, day: Int, slug: String) async throws -> PlanEditResult
    func swapExercise(plan: String, day: Int, index: Int, slug: String) async throws -> PlanEditResult
    func removeExercise(plan: String, day: Int, index: Int) async throws -> PlanEditResult
    func moveExercise(plan: String, day: Int, index: Int, up: Bool) async throws -> PlanEditResult
    func setPrescription(plan: String, day: Int, index: Int, sets: Int, reps: String, restSeconds: Int) async throws -> PlanEditResult

    func suggestions(plan: String, day: Int) async throws -> [ExerciseSummary]
    func replacements(plan: String, day: Int, index: Int) async throws -> [ExerciseSummary]
    func searchExercises(_ query: String, muscle: String?) async throws -> [ExerciseSummary]
}

struct TrainingService: TrainingServicing {
    var api: Client = API.shared

    func plans() async throws -> [PlanSummary] {
        try await NorthAPI.call { try await api.listPlans().ok.body.json.plans }
    }

    func plan(_ id: String) async throws -> PlanDetail {
        try await NorthAPI.call { try await api.getPlan(path: .init(planID: id)).ok.body.json }
    }

    func latestIntake() async throws -> TrainingIntake? {
        // NorthAPI.call throws APIError (typed), so the error needs no cast.
        // A `catch let … as … where` here crashes the Swift 6.2.3 compiler.
        do {
            return try await NorthAPI.call { try await api.getLatestIntake().ok.body.json }
        } catch {
            if error.isNotFound { return nil }
            throw error
        }
    }

    func createPlan(_ intake: TrainingIntake) async throws -> PlanDetail {
        try await NorthAPI.call { try await api.createPlan(body: .json(intake)).created.body.json }
    }

    func setStartTime(plan: String, day: Int, to time: String?) async throws -> PlanEditResult {
        try await edit {
            try await api.setDayStartTime(path: .init(planID: plan, day: day), body: .json(.init(startTime: time ?? "")))
        }
    }

    func addExercise(plan: String, day: Int, slug: String) async throws -> PlanEditResult {
        try await edit {
            try await api.addExerciseToDay(path: .init(planID: plan, day: day), body: .json(.init(catalogSlug: slug)))
        }
    }

    func swapExercise(plan: String, day: Int, index: Int, slug: String) async throws -> PlanEditResult {
        try await edit {
            try await api.swapExercise(path: .init(planID: plan, day: day, index: index), body: .json(.init(catalogSlug: slug)))
        }
    }

    func removeExercise(plan: String, day: Int, index: Int) async throws -> PlanEditResult {
        try await edit { try await api.removeExercise(path: .init(planID: plan, day: day, index: index)) }
    }

    func moveExercise(plan: String, day: Int, index: Int, up: Bool) async throws -> PlanEditResult {
        try await edit {
            try await api.moveExercise(path: .init(planID: plan, day: day, index: index), body: .json(.init(direction: up ? .up : .down)))
        }
    }

    func setPrescription(plan: String, day: Int, index: Int, sets: Int, reps: String, restSeconds: Int) async throws -> PlanEditResult {
        try await edit {
            try await api.setPrescription(
                path: .init(planID: plan, day: day, index: index),
                body: .json(.init(sets: sets, reps: reps, restSeconds: restSeconds))
            )
        }
    }

    func suggestions(plan: String, day: Int) async throws -> [ExerciseSummary] {
        try await NorthAPI.call { try await api.suggestExercisesForDay(path: .init(planID: plan, day: day)).ok.body.json.exercises }
    }

    func replacements(plan: String, day: Int, index: Int) async throws -> [ExerciseSummary] {
        try await NorthAPI.call {
            try await api.suggestReplacements(path: .init(planID: plan, day: day, index: index)).ok.body.json.exercises
        }
    }

    func searchExercises(_ query: String, muscle: String?) async throws -> [ExerciseSummary] {
        try await NorthAPI.call {
            try await api.searchExercises(query: .init(q: query.isEmpty ? nil : query, muscle: muscle, limit: 60)).ok.body.json.exercises
        }
    }

    /// Every edit answers with a plan: 200 with the version it made, or 409
    /// with the newest one when the version edited had been replaced.
    private func edit<Output: PlanEditOutput>(_ call: @escaping () async throws -> Output) async throws -> PlanEditResult {
        try await NorthAPI.call {
            let output = try await call()
            if let saved = try output.savedPlan { return .saved(saved) }
            if let newest = try output.supersededPlan { return .superseded(newest) }
            throw APIError.invalidResponse
        }
    }
}

/// The two plan-bearing answers every edit operation's generated Output has.
protocol PlanEditOutput: Sendable {
    var savedPlan: PlanDetail? { get throws }
    var supersededPlan: PlanDetail? { get throws }
}

// Each edit's generated answer: the version it made (200), or the newest
// version when the one edited had been replaced (409).
extension Operations.SetDayStartTime.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}

extension Operations.AddExerciseToDay.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}

extension Operations.SwapExercise.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}

extension Operations.RemoveExercise.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}

extension Operations.MoveExercise.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}

extension Operations.SetPrescription.Output: PlanEditOutput {
    var savedPlan: PlanDetail? {
        get throws { if case .ok(let ok) = self { try ok.body.json } else { nil } }
    }
    var supersededPlan: PlanDetail? {
        get throws { if case .conflict(let conflict) = self { try conflict.body.json } else { nil } }
    }
}
