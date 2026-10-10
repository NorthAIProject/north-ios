import NorthAPI

typealias FoodLog = Components.Schemas.FoodLog
typealias Ingredient = Components.Schemas.Ingredient
typealias MealPlanSummary = Components.Schemas.MealPlanSummary
typealias MealPlanDetail = Components.Schemas.MealPlanDetail
typealias MealPlanDay = Components.Schemas.MealPlanDay
typealias MealPlanMeal = Components.Schemas.MealPlanMeal
typealias MealPlanOption = Components.Schemas.MealPlanOption
typealias MealPortion = Components.Schemas.MealPortion
typealias MealPlanType = Components.Schemas.MealPlanType
typealias MealPlanMode = Components.Schemas.MealPlanMode
typealias MealPlanOptions = Components.Schemas.MealPlanOptions
typealias MealPlanRequest = Components.Schemas.MealPlanRequest
typealias MealPlanUpdate = Components.Schemas.MealPlanUpdate
typealias MealPlanDayOverride = Components.Schemas.MealPlanDayOverride
typealias MealDayStatus = Components.Schemas.MealDayStatus
typealias MacroOverage = Components.Schemas.MacroOverage
typealias Macros = Components.Schemas.Macros
typealias FoodDraft = Components.Schemas.FoodDraft
typealias FoodLine = Components.Schemas.FoodLine

/// What a change to a meal plan came back with: saved, or refused because a
/// day would go further over its target. The server decides which; an
/// advanced plan's overage can be sent again confirmed, an easy plan's not.
enum PlanWrite<Saved: Sendable>: Sendable {
    case saved(Saved)
    case over(MacroOverage)
}

protocol NutritionServicing: Sendable {
    func log() async throws -> FoodLog
    func logFood(_ ingredientID: String, grams: Double) async throws -> FoodLog
    func logMeal(_ mealID: String) async throws -> FoodLog
    func deleteEntry(_ id: String) async throws -> FoodLog
    func ingredients(matching query: String) async throws -> [Ingredient]
    func createIngredient(name: String, per100g: Macros) async throws
    func deleteIngredient(_ id: String) async throws
    func planOptions() async throws -> MealPlanOptions
    func plans() async throws -> [MealPlanSummary]
    func plan(_ id: String) async throws -> MealPlanDetail
    func createPlan(_ request: MealPlanRequest) async throws -> MealPlanDetail
    func updatePlan(_ id: String, _ update: MealPlanUpdate) async throws -> PlanWrite<MealPlanDetail>
    func deletePlan(_ id: String) async throws
    func addDay(to planID: String, weekday: Int?) async throws -> MealPlanDetail
    func updateDay(_ id: String, _ override: MealPlanDayOverride) async throws -> PlanWrite<MealPlanDetail>
    func removeDay(_ id: String) async throws
    func addMeal(to dayID: String, name: String) async throws -> MealPlanDetail
    func removeMeal(_ id: String) async throws
    func addPortions(to mealID: String, _ portions: [(ingredientID: String, grams: Double)], confirm: Bool) async throws -> PlanWrite<Void>
    func removePortion(_ id: String) async throws
    func parseFoods(_ text: String) async throws -> FoodDraft
}

struct NutritionService: NutritionServicing {
    var api: Client = API.shared

    func log() async throws -> FoodLog { try await NorthAPI.call { try await api.getFoodLog().ok.body.json } }
    func logFood(_ ingredientID: String, grams: Double) async throws -> FoodLog {
        try await NorthAPI.call { try await api.logFood(body: .json(.init(ingredientId: ingredientID, quantityGrams: grams))).created.body.json }
    }
    func logMeal(_ mealID: String) async throws -> FoodLog {
        try await NorthAPI.call { try await api.logPlanMeal(body: .json(.init(mealId: mealID))).created.body.json }
    }
    func deleteEntry(_ id: String) async throws -> FoodLog {
        try await NorthAPI.call { try await api.deleteFoodLogEntry(path: .init(entryID: id)).ok.body.json }
    }
    func ingredients(matching query: String) async throws -> [Ingredient] {
        try await NorthAPI.call { try await api.searchIngredients(query: .init(q: query.isEmpty ? nil : query)).ok.body.json.ingredients }
    }
    func createIngredient(name: String, per100g: Macros) async throws {
        try await NorthAPI.call { _ = try await api.createIngredient(body: .json(.init(name: name, per100g: per100g))).created }
    }
    func deleteIngredient(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteIngredient(path: .init(ingredientID: id)).noContent }
    }
    func planOptions() async throws -> MealPlanOptions {
        try await NorthAPI.call { try await api.getMealPlanOptions().ok.body.json }
    }
    func plans() async throws -> [MealPlanSummary] { try await NorthAPI.call { try await api.listMealPlans().ok.body.json.plans } }
    func plan(_ id: String) async throws -> MealPlanDetail {
        try await NorthAPI.call { try await api.getMealPlan(path: .init(planID: id)).ok.body.json }
    }
    func createPlan(_ request: MealPlanRequest) async throws -> MealPlanDetail {
        try await NorthAPI.call { try await api.createMealPlan(body: .json(request)).created.body.json }
    }
    func updatePlan(_ id: String, _ update: MealPlanUpdate) async throws -> PlanWrite<MealPlanDetail> {
        try await NorthAPI.call {
            switch try await api.updateMealPlan(path: .init(planID: id), body: .json(update)) {
            case .ok(let ok): .saved(try ok.body.json)
            case .conflict(let conflict): .over(try conflict.body.json)
            default: throw APIError.invalidResponse
            }
        }
    }
    func deletePlan(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteMealPlan(path: .init(planID: id)).noContent }
    }
    func addDay(to planID: String, weekday: Int?) async throws -> MealPlanDetail {
        try await NorthAPI.call {
            try await api.addMealPlanDay(path: .init(planID: planID), body: .json(.init(weekday: weekday))).created.body.json
        }
    }
    func updateDay(_ id: String, _ override: MealPlanDayOverride) async throws -> PlanWrite<MealPlanDetail> {
        try await NorthAPI.call {
            switch try await api.updateMealPlanDay(path: .init(dayID: id), body: .json(override)) {
            case .ok(let ok): .saved(try ok.body.json)
            case .conflict(let conflict): .over(try conflict.body.json)
            default: throw APIError.invalidResponse
            }
        }
    }
    func removeDay(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.removeMealPlanDay(path: .init(dayID: id)).noContent }
    }
    func addMeal(to dayID: String, name: String) async throws -> MealPlanDetail {
        try await NorthAPI.call { try await api.addPlanMeal(path: .init(dayID: dayID), body: .json(.init(name: name))).created.body.json }
    }
    func removeMeal(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.removePlanMeal(path: .init(mealID: id)).noContent }
    }
    func addPortions(to mealID: String, _ portions: [(ingredientID: String, grams: Double)], confirm: Bool) async throws -> PlanWrite<Void> {
        let lines = portions.map { Components.Schemas.PortionLine(ingredientId: $0.ingredientID, quantityGrams: $0.grams) }
        return try await NorthAPI.call {
            switch try await api.addMealPortions(path: .init(mealID: mealID), body: .json(.init(portions: lines, confirmOverage: confirm))) {
            case .created: .saved(())
            case .conflict(let conflict): .over(try conflict.body.json)
            default: throw APIError.invalidResponse
            }
        }
    }
    func removePortion(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.removeMealPortion(path: .init(mealIngredientID: id)).noContent }
    }
    func parseFoods(_ text: String) async throws -> FoodDraft {
        try await NorthAPI.call { try await api.parseMealFoods(body: .json(.init(text: text))).ok.body.json }
    }
}
