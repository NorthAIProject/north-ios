import Foundation
import NorthAPI
import Testing
@testable import khepri

@MainActor
struct MealPlanTests {
    private static let planID = "11111111-0000-0000-0000-000000000000"
    private static let monday = "22222222-0000-0000-0000-000000000000"
    private static let breakfast = "33333333-0000-0000-0000-000000000000"
    private static let oats = Macros(calories: 380, proteinG: 13, fatG: 7, carbG: 68)

    /// A plan with one Monday breakfast and 30 g of carbs left that day.
    private static func plan(mode: MealPlanMode, carbsLeft: Double = 30) -> MealPlanDetail {
        let target = Macros(calories: 1600, proteinG: 150, fatG: 70, carbG: 40)
        let consumed = Macros(calories: 40, proteinG: 0, fatG: 0, carbG: 40 - carbsLeft)
        let remaining = Macros(calories: 1560, proteinG: 150, fatG: 70, carbG: carbsLeft)
        return MealPlanDetail(
            value1: .init(id: planID, name: "Week", description: "", planType: .lowCarb, mode: mode, dayCount: 1, totalMacros: consumed),
            value2: .init(objective: "", activityLevel: "", gender: "", target: target, days: [
                .init(id: monday, weekday: 1,
                      status: .init(target: target, consumed: consumed, remaining: remaining,
                                    over: .init(calories: 0, proteinG: 0, fatG: 0, carbG: 0), isOver: false),
                      meals: [.init(id: breakfast, mealNumber: 1, name: "Breakfast", totalMacros: consumed, ingredients: [])]),
            ])
        )
    }

    private static func overage(canConfirm: Bool) -> MacroOverage {
        MacroOverage(message: "Monday would be 4 g over on carbs.", canConfirm: canConfirm, days: [
            .init(dayId: monday, weekday: 1,
                  target: .init(calories: 1600, proteinG: 150, fatG: 70, carbG: 40),
                  consumed: .init(calories: 200, proteinG: 0, fatG: 0, carbG: 44),
                  over: .init(calories: 0, proteinG: 0, fatG: 0, carbG: 4)),
        ])
    }

    private func loadedStore(_ fake: FakeNutrition) async -> MealPlanStore {
        let store = MealPlanStore(id: Self.planID, service: fake)
        await store.load()
        return store
    }

    @Test func anAdvancedOverageWaitsForConfirmationThenResendsConfirmed() async {
        let fake = FakeNutrition(plan: Self.plan(mode: .advanced))
        fake.portionAnswers = [.over(Self.overage(canConfirm: true)), .saved(())]
        let store = await loadedStore(fake)

        let saved = await store.addPortions(to: Self.breakfast, [("oats", 50)])

        #expect(!saved)
        #expect(store.pendingOverage?.overage.canConfirm == true)
        #expect(fake.portionConfirms == [false])

        await store.pendingOverage?.resend()

        #expect(fake.portionConfirms == [false, true])
        #expect(store.pendingOverage == nil)
    }

    @Test func anEasyOverageCannotBeConfirmed() async {
        let fake = FakeNutrition(plan: Self.plan(mode: .easy))
        fake.portionAnswers = [.over(Self.overage(canConfirm: false))]
        let store = await loadedStore(fake)

        await store.addPortions(to: Self.breakfast, [("oats", 50)])

        #expect(store.pendingOverage?.overage.canConfirm == false)
        #expect(store.pendingOverage?.overage.explanation.contains("4 g over on carbs (44 of 40 g)") == true)
    }

    @Test func thePreviewSubtractsThePortionFromWhatTheDayHasLeft() async {
        let store = await loadedStore(FakeNutrition(plan: Self.plan(mode: .easy, carbsLeft: 30)))

        #expect(store.remaining(on: Self.monday)?.carbG == 30)
        // 50 g of oats is 34 g of carbs: 4 g past what is left.
        let after = store.remaining(on: Self.monday, after: Self.oats, grams: 50)
        #expect(after?.carbG == -4)
        #expect(after?.proteinG == 150 - 6.5)
    }

    @Test func switchingToEasyConfirmsTheReset() async {
        let fake = FakeNutrition(plan: Self.plan(mode: .advanced))
        let store = await loadedStore(fake)

        await store.switchToEasy(planType: .midCarb)

        #expect(fake.updates.last?.mode == .easy)
        #expect(fake.updates.last?.confirmReset == true)
        #expect(fake.updates.last?.planType == .midCarb)
    }

    @Test func aDayOverrideIsSentAsTheDayAsked() async {
        let fake = FakeNutrition(plan: Self.plan(mode: .advanced))
        let store = await loadedStore(fake)

        await store.updateDay(Self.monday, MealPlanDayOverride(carbType: .highCarb))

        #expect(fake.dayOverrides.last?.carbType == .highCarb)
        #expect(fake.dayOverrides.last?.confirmOverage == false)
    }
}

/// A nutrition service that answers from memory.
private final class FakeNutrition: NutritionServicing, @unchecked Sendable {
    var plan: MealPlanDetail
    var portionAnswers: [PlanWrite<Void>] = []
    var portionConfirms: [Bool] = []
    var updates: [MealPlanUpdate] = []
    var dayOverrides: [MealPlanDayOverride] = []

    init(plan: MealPlanDetail) { self.plan = plan }

    func plan(_ id: String) async throws -> MealPlanDetail { plan }
    func addPortions(to mealID: String, _ portions: [(ingredientID: String, grams: Double)], confirm: Bool) async throws -> PlanWrite<Void> {
        portionConfirms.append(confirm)
        return portionAnswers.isEmpty ? .saved(()) : portionAnswers.removeFirst()
    }
    func updatePlan(_ id: String, _ update: MealPlanUpdate) async throws -> PlanWrite<MealPlanDetail> {
        updates.append(update)
        return .saved(plan)
    }
    func updateDay(_ id: String, _ override: MealPlanDayOverride) async throws -> PlanWrite<MealPlanDetail> {
        dayOverrides.append(override)
        return .saved(plan)
    }

    struct Unused: Error {}
    func log() async throws -> FoodLog { throw Unused() }
    func logFood(_ ingredientID: String, grams: Double) async throws -> FoodLog { throw Unused() }
    func logMeal(_ mealID: String) async throws -> FoodLog { throw Unused() }
    func deleteEntry(_ id: String) async throws -> FoodLog { throw Unused() }
    func ingredients(matching query: String) async throws -> [Ingredient] { [] }
    func createIngredient(name: String, per100g: Macros) async throws {}
    func deleteIngredient(_ id: String) async throws {}
    func planOptions() async throws -> MealPlanOptions { throw Unused() }
    func plans() async throws -> [MealPlanSummary] { [] }
    func createPlan(_ request: MealPlanRequest) async throws -> MealPlanDetail { plan }
    func deletePlan(_ id: String) async throws {}
    func addDay(to planID: String, weekday: Int?) async throws -> MealPlanDetail { plan }
    func removeDay(_ id: String) async throws {}
    func addMeal(to dayID: String, name: String) async throws -> MealPlanDetail { plan }
    func removeMeal(_ id: String) async throws {}
    func removePortion(_ id: String) async throws {}
    func parseFoods(_ text: String) async throws -> FoodDraft { throw Unused() }
}
