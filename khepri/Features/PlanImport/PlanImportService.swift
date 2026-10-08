import Foundation
import NorthAPI
import OpenAPIRuntime
import UIKit
import UniformTypeIdentifiers

typealias WorkoutImportDraft = Components.Schemas.WorkoutImportDraft
typealias WorkoutImportDay = Components.Schemas.WorkoutImportDay
typealias WorkoutImportExercise = Components.Schemas.WorkoutImportExercise
typealias MealImportDraft = Components.Schemas.MealImportDraft
typealias MealImportDay = Components.Schemas.MealImportDay
typealias MealImportMeal = Components.Schemas.MealImportMeal
typealias MealImportFood = Components.Schemas.MealImportFood
typealias ImportMacros = Components.Schemas.ImportMacros

/// Reading a plan out of a file, and saving it once the person has checked it.
///
/// The server reads; this only carries bytes and drafts. Nothing is stored
/// until `commitWorkout`, so dropping a draft is all cancelling takes.
protocol PlanImportServicing: Sendable {
    /// The server picks the reader from the filename's extension and checks
    /// the bytes agree, so the name matters.
    func parseWorkout(filename: String, data: Data) async throws -> WorkoutImportDraft
    /// Saves the reviewed draft as a new plan and returns its id.
    func commitWorkout(_ draft: WorkoutImportDraft) async throws -> String

    /// Reads a meal plan and previews it against the macro target.
    func parseMeal(filename: String, data: Data) async throws -> MealImportDraft
    /// Recomputes an edited draft: ingredients, grams, each day's target and
    /// overage. Writes nothing.
    func previewMeal(_ draft: MealImportDraft) async throws -> MealImportDraft
    /// Saves the reviewed draft as a new plan, or reports the days over their
    /// target exactly as any other meal plan change would.
    func commitMeal(_ draft: MealImportDraft, confirm: Bool) async throws -> PlanWrite<String>
}

struct PlanImportService: PlanImportServicing {
    var api: Client = API.shared
    /// Documents and photos are read by a model, which can take a while.
    var generationAPI: Client = API.generation

    func parseWorkout(filename: String, data: Data) async throws -> WorkoutImportDraft {
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.ParseWorkoutImport.Input.Body.MultipartFormPayload.FilePayload(body: HTTPBody(data)),
            filename: filename
        )
        return try await NorthAPI.call {
            try await generationAPI.parseWorkoutImport(body: .multipartForm([.file(part)])).ok.body.json
        }
    }

    func commitWorkout(_ draft: WorkoutImportDraft) async throws -> String {
        try await NorthAPI.call { try await api.commitWorkoutImport(body: .json(draft)).created.body.json.planId }
    }

    func parseMeal(filename: String, data: Data) async throws -> MealImportDraft {
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.ParseMealImport.Input.Body.MultipartFormPayload.FilePayload(body: HTTPBody(data)),
            filename: filename
        )
        return try await NorthAPI.call {
            try await generationAPI.parseMealImport(body: .multipartForm([.file(part)])).ok.body.json
        }
    }

    func previewMeal(_ draft: MealImportDraft) async throws -> MealImportDraft {
        try await NorthAPI.call { try await api.previewMealImport(body: .json(draft)).ok.body.json }
    }

    func commitMeal(_ draft: MealImportDraft, confirm: Bool) async throws -> PlanWrite<String> {
        try await NorthAPI.call {
            switch try await api.commitMealImport(body: .json(.init(draft: draft, confirmOverage: confirm))) {
            case .created(let created): .saved(try created.body.json.planId)
            case .conflict(let conflict): .over(try conflict.body.json)
            default: throw APIError.invalidResponse
            }
        }
    }
}

/// A file or photo on its way to the server.
struct ImportFile: Equatable {
    var filename: String
    var data: Data

    /// The largest upload the server takes.
    static let maxBytes = 10 * 1024 * 1024

    /// The kinds the server reads. Legacy .xls is offered so the server can
    /// say how to convert it, rather than the picker silently greying it out.
    static let fileTypes: [UTType] = [
        .pdf, .plainText, .commaSeparatedText, .tabSeparatedText, .json, .image,
        UTType(filenameExtension: "md"), UTType(filenameExtension: "docx"),
        UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")
    ].compactMap { $0 }

    /// A photo becomes a JPEG no larger than it needs to be read. HEIC and
    /// WEBP are what the camera and the web produce, and not every model the
    /// server may ask can open them; a JPEG every model can.
    static func photo(_ image: UIImage, name: String = "photo") -> ImportFile? {
        let longest: CGFloat = 2400
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return ImportFile(filename: "\(name).jpg", data: data)
    }

    /// Reads a file the person picked in Files. Images go through `photo` for
    /// the reason it gives.
    static func picked(_ url: URL) throws -> ImportFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let image = UIImage(data: data) {
            return photo(image, name: url.deletingPathExtension().lastPathComponent)
        }
        return ImportFile(filename: url.lastPathComponent, data: data)
    }
}

/// A draft being reviewed, with stable identities for its rows.
///
/// The generated types compare by value, so using them as list identity would
/// give a row a new identity on every keystroke and drop the keyboard focus.
struct EditableWorkoutDraft {
    var name: String
    var days: [Day]
    var unparsed: [String]

    struct Day: Identifiable {
        let id = UUID()
        var label: String
        var weekday: String
        var exercises: [Item]
    }

    struct Item: Identifiable {
        let id = UUID()
        var exercise: WorkoutImportExercise
    }

    init(_ draft: WorkoutImportDraft) {
        name = draft.name
        unparsed = draft.unparsed
        days = draft.days.map { day in
            Day(label: day.label, weekday: day.weekday, exercises: day.exercises.map { Item(exercise: $0) })
        }
    }

    var draft: WorkoutImportDraft {
        WorkoutImportDraft(
            name: name,
            days: days.map { day in
                WorkoutImportDay(label: day.label, weekday: day.weekday, exercises: day.exercises.map(\.exercise))
            },
            unparsed: unparsed
        )
    }

    /// Every day has its own weekday and every exercise a name: what saving
    /// needs.
    var isReadyToSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !days.isEmpty
            && days.allSatisfy { !$0.weekday.isEmpty && !$0.exercises.isEmpty }
            && days.allSatisfy { day in
                day.exercises.allSatisfy { !$0.exercise.name.trimmingCharacters(in: .whitespaces).isEmpty }
            }
            && Set(days.map(\.weekday)).count == days.count
    }

    /// Some exercise has no set count, so it won't appear in a live workout.
    var hasMissingSets: Bool {
        days.contains { $0.exercises.contains { $0.exercise.sets == nil } }
    }
}
