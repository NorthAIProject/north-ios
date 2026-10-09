import Foundation
import NorthAPI

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
