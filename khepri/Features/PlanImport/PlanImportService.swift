import Foundation
import NorthAPI
import OpenAPIRuntime

struct PlanImportService: PlanImportServicing {
    var api: Client = API.shared
    /// Documents and photos are read by a model, which can take a while.
    var generationAPI: Client = API.generation

    func parseWorkout(filename: String, data: Data) async throws -> WorkoutImportDraft {
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.ParseWorkoutImport.Input.Body.MultipartFormPayload.FilePayload(body: HTTPBody(data)),
            filename: filename
        )
        return try await BackgroundActivity.run("Workout import") {
            try await NorthAPI.call {
                try await generationAPI.parseWorkoutImport(body: .multipartForm([.file(part)])).ok.body.json
            }
        }
    }

    func commitWorkout(_ draft: WorkoutImportDraft) async throws -> String {
        try await BackgroundActivity.run("Workout import") {
            try await NorthAPI.call { try await api.commitWorkoutImport(body: .json(draft)).created.body.json.planId }
        }
    }

    func parseMeal(filename: String, data: Data) async throws -> MealImportDraft {
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.ParseMealImport.Input.Body.MultipartFormPayload.FilePayload(body: HTTPBody(data)),
            filename: filename
        )
        return try await BackgroundActivity.run("Meal import") {
            try await NorthAPI.call {
                try await generationAPI.parseMealImport(body: .multipartForm([.file(part)])).ok.body.json
            }
        }
    }

    func previewMeal(_ draft: MealImportDraft) async throws -> MealImportDraft {
        try await BackgroundActivity.run("Meal import") {
            try await NorthAPI.call { try await api.previewMealImport(body: .json(draft)).ok.body.json }
        }
    }

    func commitMeal(_ draft: MealImportDraft, confirm: Bool) async throws -> PlanWrite<String> {
        try await BackgroundActivity.run("Meal import") {
            try await NorthAPI.call {
                switch try await api.commitMealImport(body: .json(.init(draft: draft, confirmOverage: confirm))) {
                case .created(let created): .saved(try created.body.json.planId)
                case .conflict(let conflict): .over(try conflict.body.json)
                default: throw APIError.invalidResponse
                }
            }
        }
    }
}
