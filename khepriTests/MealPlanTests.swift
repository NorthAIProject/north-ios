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

    // MARK: Meal options

    private static let lunch = "44444444-0000-0000-0000-000000000000"
    private static let lunchFish = "55555555-0000-0000-0000-000000000000"
    private static let lunchTofu = "66666666-0000-0000-0000-000000000000"

    /// A Monday with a plain breakfast and a lunch of three options, and the
    /// notes an imported plan carries.
    private static func planWithOptions(notes: String? = "  Beber 2 L de água.\n") -> MealPlanDetail {
        let chicken = Macros(calories: 165, proteinG: 31, fatG: 3.6, carbG: 0)
        let fish = Macros(calories: 206, proteinG: 44, fatG: 2, carbG: 0)
        let cod = MealPortion(id: "77777777-0000-0000-0000-000000000000", ingredientId: "cod", name: "Cod",
                              quantityGrams: 250, macros: fish, sourceText: "peixe branco à vontade", estimated: true)
        var plan = plan(mode: .easy)
        plan.value2.notes = notes
        plan.value2.days[0].meals.append(.init(
            id: lunch, mealNumber: 2, name: "Almoço", optionLabel: "Opção 1", totalMacros: chicken, ingredients: [],
            alternatives: [
                .init(id: lunchFish, optionLabel: "Opção 2", totalMacros: fish, ingredients: [cod]),
                .init(id: lunchTofu, optionLabel: "", totalMacros: chicken, ingredients: [])
            ]
        ))
        return plan
    }

    /// The options plan with a Tuesday copy of Monday, as an every-day
    /// import saves the same meals on each weekday.
    private static func twoDayPlanWithOptions() -> MealPlanDetail {
        var plan = planWithOptions()
        var tuesday = plan.value2.days[0]
        tuesday.id = "88888888-0000-0000-0000-000000000000"
        tuesday.weekday = 2
        tuesday.meals = tuesday.meals.map { meal in
            var meal = meal
            meal.id = "t-" + meal.id
            meal.alternatives = meal.alternatives?.map { var option = $0; option.id = "t-" + option.id; return option }
            return meal
        }
        plan.value2.days.append(tuesday)
        return plan
    }

    @Test func theLogListOffersOnlyTodaysOptionsEachByItsOwnID() {
        let meals = Self.twoDayPlanWithOptions().loggableMeals(today: 1)

        #expect(meals.map(\.id) == [Self.breakfast, Self.lunch, Self.lunchFish, Self.lunchTofu])
        #expect(meals.map(\.title) == [
            "Week · Breakfast",
            "Week · Almoço · Opção 1",
            "Week · Almoço · Opção 2",
            "Week · Almoço · Option 3"
        ])
        #expect(meals[2].calories == 206)
    }

    @Test func aPlanWithNoDayForTodayOffersEveryDayByWeekday() {
        let meals = Self.twoDayPlanWithOptions().loggableMeals(today: 0)
        let weekdays = Calendar.current.standaloneWeekdaySymbols

        #expect(meals.count == 8)
        #expect(meals.map(\.id).prefix(4) == [Self.breakfast, Self.lunch, Self.lunchFish, Self.lunchTofu])
        #expect(meals.map(\.id).suffix(4).allSatisfy { $0.hasPrefix("t-") })
        #expect(meals[0].title == "Week · \(weekdays[1]) · Breakfast")
        #expect(meals[7].title == "Week · \(weekdays[2]) · Almoço · Option 3")
    }

    @Test func anAlternativeIsFoundButNeverCountsTowardItsDay() async {
        let store = await loadedStore(FakeNutrition(plan: Self.planWithOptions()))

        #expect(store.day(holding: Self.lunch)?.id == Self.monday)
        #expect(store.day(holding: Self.lunchFish) == nil)
        #expect(store.isAlternative(Self.lunchFish))
        #expect(!store.isAlternative(Self.lunch))
        #expect(!store.isAlternative(Self.breakfast))
    }

    @Test func aMealsOptionsPutTheCountedFirstThenItsAlternatives() throws {
        let lunch = try #require(Self.planWithOptions().value2.days[0].meals.last)

        #expect(lunch.hasAlternatives)
        #expect(lunch.options.map(\.label) == ["Opção 1", "Opção 2", "Option 3"])
        #expect(lunch.options.map(\.isCounted) == [true, false, false])
        #expect(lunch.options[1].ingredients.first?.estimated == true)
        #expect(!(Self.plan(mode: .easy).value2.days[0].meals[0].hasAlternatives))
    }

    @Test func planNotesAreTrimmedAndBlankNotesAreNone() async {
        #expect(await loadedStore(FakeNutrition(plan: Self.planWithOptions())).notes == "Beber 2 L de água.")
        #expect(await loadedStore(FakeNutrition(plan: Self.planWithOptions(notes: " \n "))).notes == nil)
        #expect(await loadedStore(FakeNutrition(plan: Self.planWithOptions(notes: nil))).notes == nil)
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
