import Foundation
import NorthAPI
import Testing
import UIKit
@testable import khepri

@MainActor
struct PlanImportTests {
    // MARK: - Fixtures

    private static func food(_ name: String, grams: Double? = 100) -> MealImportFood {
        MealImportFood(food: name, unit: "g", grams: grams, matchedName: "", saveAsMine: false)
    }

    private static func mealDraft(_ days: [[(String, [MealImportFood])]]) -> MealImportDraft {
        MealImportDraft(
            name: "Cut", planType: "low_carb", mode: "easy", hasTarget: true, canConfirm: false,
            days: days.enumerated().map { index, meals in
                MealImportDay(label: "Day \(index + 1)", meals: meals.map { MealImportMeal(name: $0.0, foods: $0.1) })
            },
            unparsed: []
        )
    }

    private static func exercise(_ name: String, sets: Int? = 3) -> WorkoutImportExercise {
        WorkoutImportExercise(name: name, sets: sets, reps: "8", load: "", notes: "")
    }

    private static func workoutDraft(_ weekdays: [String], name: String = "Strength") -> EditableWorkoutDraft {
        EditableWorkoutDraft(WorkoutImportDraft(
            name: name,
            days: weekdays.enumerated().map { index, weekday in
                WorkoutImportDay(label: "Day \(index + 1)", weekday: weekday, exercises: [exercise("Squat")])
            },
            unparsed: []
        ))
    }

    // MARK: - EditableMealDraft

    @Test func refreshedMealDraftKeepsRowIdentityByPosition() {
        let first = EditableMealDraft(Self.mealDraft([[("Breakfast", [Self.food("Oats"), Self.food("Milk")])]]))
        let refreshed = EditableMealDraft(
            Self.mealDraft([
                [("Breakfast", [Self.food("Oats", grams: 80), Self.food("Milk"), Self.food("Honey")])],
                [("Lunch", [Self.food("Rice")])]
            ]),
            keeping: first
        )

        #expect(refreshed.days[0].id == first.days[0].id)
        #expect(refreshed.days[0].meals[0].id == first.days[0].meals[0].id)
        let keptFoods = refreshed.days[0].meals[0].foods.map(\.id).prefix(2)
        #expect(keptFoods == first.days[0].meals[0].foods.map(\.id).prefix(2))
        #expect(refreshed.days[0].meals[0].foods[0].value.grams == 80)
        #expect(!first.days[0].meals[0].foods.map(\.id).contains(refreshed.days[0].meals[0].foods[2].id))
        #expect(refreshed.days[1].id != first.days[0].id)
    }

    @Test func mealDraftCarriesEditedNamesBackToTheServerShape() {
        var editable = EditableMealDraft(Self.mealDraft([[("Breakfast", [Self.food("Oats")])]]))
        editable.days[0].meals[0].name = "First meal"
        editable.settings.name = "Lean"

        let draft = editable.draft
        #expect(draft.name == "Lean")
        #expect(draft.days[0].meals[0].name == "First meal")
        #expect(draft.days[0].meals[0].foods[0].food == "Oats")
    }

    /// An every-day draft with notes and one lunch of three options, as the
    /// reader returns a nutritionist's PDF.
    private static func optionsDraft() -> MealImportDraft {
        var chicken = food("Chicken breast", grams: 150)
        chicken.sourceText = "150 g frango grelhado"
        var fish = food("Cod", grams: 250)
        fish.sourceText = "peixe branco à vontade"
        fish.estimated = true
        let lunch = MealImportMeal(
            name: "Almoço", foods: [chicken], optionLabel: "Opção 1",
            alternatives: [
                MealImportOption(label: "Opção 2", foods: [fish]),
                MealImportOption(label: "", foods: [food("Tofu"), food("Rice")])
            ]
        )
        return MealImportDraft(
            name: "Plano", planType: "mid_carb", mode: "advanced", hasTarget: true, canConfirm: false,
            days: [MealImportDay(
                label: "Every day", weekday: 1,
                meals: [lunch, MealImportMeal(name: "Snack", foods: [food("Apple")])]
            )],
            unparsed: [], everyDay: true, notes: "Beber 2 L de água.\nSem açúcar."
        )
    }

    @Test func mealDraftRoundTripsOptionsEveryDayNotesAndSourceLinesUnchanged() {
        let sent = Self.optionsDraft()
        let editable = EditableMealDraft(sent)

        #expect(editable.draft == sent)
        #expect(editable.isEveryDay)
        #expect(editable.notes == "Beber 2 L de água.\nSem açúcar.")
        let lunch = editable.days[0].meals[0]
        #expect(lunch.firstOptionTitle == "Opção 1")
        #expect(lunch.alternatives.map { lunch.title(of: $0.id) } == ["Opção 2", "Option 3"])
        // A meal sent without alternatives goes back without them, not as [].
        #expect(editable.draft.days[0].meals[1].alternatives == nil)
    }

    @Test func mealDraftCarriesEditsToAnAlternativeAndKeepsTheRestThroughAPreview() {
        var editable = EditableMealDraft(Self.optionsDraft())
        editable.days[0].meals[0].alternatives[0].foods[0].value.grams = 200
        editable.days[0].meals[0].name = "Lunch"

        let sent = editable.draft
        let alternative = sent.days[0].meals[0].alternatives?.first
        #expect(alternative?.label == "Opção 2")
        #expect(alternative?.foods.first?.grams == 200)
        #expect(alternative?.foods.first?.sourceText == "peixe branco à vontade")
        #expect(alternative?.foods.first?.estimated == true)
        #expect(sent.days[0].meals[0].optionLabel == "Opção 1")
        #expect(sent.everyDay == true && sent.notes == "Beber 2 L de água.\nSem açúcar.")

        // The server's answer to that preview keeps every row where it was.
        let refreshed = EditableMealDraft(sent, keeping: editable)
        #expect(refreshed.draft == sent)
        #expect(refreshed.days[0].meals[0].alternatives.map(\.id) == editable.days[0].meals[0].alternatives.map(\.id))
        let oldFoods = editable.days[0].meals[0].alternatives[1].foods.map(\.id)
        #expect(refreshed.days[0].meals[0].alternatives[1].foods.map(\.id) == oldFoods)
    }

    @Test func emptyingAnAlternativeRemovesOnlyThatOption() {
        var meal = EditableMealDraft(Self.optionsDraft()).days[0].meals[0]
        let fish = meal.alternatives[0].id

        meal.removeFoods(atOffsets: [0], fromAlternative: fish)

        #expect(meal.alternatives.count == 1)
        #expect(meal.foods.map(\.value.food) == ["Chicken breast"])
        #expect(meal.title(of: meal.alternatives[0].id) == "Option 2")
    }

    @Test func emptyingTheFirstOptionPromotesTheNextAsSavingWould() {
        var meal = EditableMealDraft(Self.optionsDraft()).days[0].meals[0]

        meal.removeFoods(atOffsets: [0])

        #expect(meal.foods.map(\.value.food) == ["Cod"])
        #expect(meal.firstOptionTitle == "Opção 2")
        #expect(meal.alternatives.count == 1)
        #expect(!meal.isEmpty)

        meal.removeFoods(atOffsets: [0])
        meal.removeFoods(atOffsets: [0, 1])
        #expect(meal.isEmpty)
    }

    // MARK: - EditableWorkoutDraft

    @Test func workoutDraftIsReadyWithDistinctWeekdaysAndANamedPlan() {
        #expect(Self.workoutDraft(["Monday", "Thursday"]).isReadyToSave)
    }

    @Test func workoutDraftIsNotReadyWithABlankWeekdayOrName() {
        #expect(!Self.workoutDraft(["Monday", ""]).isReadyToSave)
        #expect(!Self.workoutDraft(["Monday"], name: "  ").isReadyToSave)
    }

    @Test func workoutDraftNamesRepeatedWeekdaysAndRefusesThem() {
        let draft = Self.workoutDraft(["Monday", "Monday", "Friday", "", ""])
        #expect(draft.repeatedWeekdays == ["Monday"])
        #expect(!draft.isReadyToSave)
    }

    @Test func workoutDraftFlagsExercisesWithoutASetCount() {
        var draft = Self.workoutDraft(["Monday"])
        #expect(!draft.hasMissingSets)
        draft.days[0].exercises[0].exercise.sets = nil
        #expect(draft.hasMissingSets)
    }

    // MARK: - ImportFile

    private static func image(width: Double, height: Double) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private static func pixelSize(_ file: ImportFile) throws -> CGSize {
        let decoded = try #require(UIImage(data: file.data))
        return CGSize(width: decoded.size.width * decoded.scale, height: decoded.size.height * decoded.scale)
    }

    @Test func largePhotoShrinksToTheLongestSideInPixels() async throws {
        let file = try #require(await ImportFile.photo(Self.image(width: 4000, height: 3000)))
        #expect(try Self.pixelSize(file) == CGSize(width: 2400, height: 1800))
        #expect(file.filename == "photo.jpg")
    }

    @Test func smallPhotoIsNotUpscaled() async throws {
        let file = try #require(await ImportFile.photo(Self.image(width: 800, height: 600)))
        #expect(try Self.pixelSize(file) == CGSize(width: 800, height: 600))
    }

    // MARK: - importMessage

    @Test func importMessagePrefersTheServersFieldSentence() {
        let refused = APIError.fieldValidation(
            message: "Invalid upload.",
            fields: ["file": "This PDF is password-protected."]
        )
        #expect(refused.importMessage == "This PDF is password-protected.")
        let plain = APIError.fieldValidation(message: "Invalid upload.", fields: [:])
        #expect(plain.importMessage == "Invalid upload.")
    }
}
