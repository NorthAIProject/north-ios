import Foundation
import NorthAPI
import Observation

/// One meal plan being shaped: its days, what each has left of its target,
/// and any change the server refused for going over.
///
/// The server owns every rule — targets, ranges, what counts as over. This
/// only shows its answers, and for a portion still being chosen, subtracts it
/// from what the server said the day has left.
@MainActor
@Observable
final class MealPlanStore {
    /// A change refused for taking a day over its target. `resend` sends the
    /// same change again, confirmed; it is only offered when the server says
    /// the plan allows it.
    struct PendingOverage {
        let overage: MacroOverage
        let resend: @MainActor () async -> Void
    }

    let id: String
    private let service: NutritionServicing

    private(set) var plan: MealPlanDetail?
    var error: String?
    var pendingOverage: PendingOverage?

    init(id: String, service: NutritionServicing) {
        self.id = id
        self.service = service
    }

    var days: [MealPlanDay] { plan?.value2.days ?? [] }
    var isAdvanced: Bool { plan?.value1.mode == .advanced }
    var hasTarget: Bool { plan?.value2.target != nil }

    /// The advice an imported plan carried beside its meals; nil when blank.
    var notes: String? {
        let notes = plan?.value2.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? nil : notes
    }

    func load() async {
        do { plan = try await service.plan(id); error = nil } catch { self.error = error.localizedDescription }
    }

    // MARK: Changes the overage rule checks

    /// Adds portions to a meal together, as one change. True once they are
    /// saved; false when refused, with `pendingOverage` or `error` set.
    @discardableResult
    func addPortions(to mealID: String, _ portions: [(ingredientID: String, grams: Double)]) async -> Bool {
        await write { confirm in try await self.service.addPortions(to: mealID, portions, confirm: confirm) }
    }

    @discardableResult
    func updateDay(_ dayID: String, _ override: MealPlanDayOverride) async -> Bool {
        await write { confirm in
            var override = override
            override.confirmOverage = confirm
            return try await self.service.updateDay(dayID, override)
        }
    }

    @discardableResult
    func updateSettings(name: String, planType: MealPlanType, customCarbPct: Double?) async -> Bool {
        guard let mode = plan?.value1.mode else { return false }
        return await saveSettings(name: name, planType: planType, customCarbPct: customCarbPct, mode: mode, confirmReset: false)
    }

    @discardableResult
    func switchToAdvanced() async -> Bool {
        guard let summary = plan?.value1 else { return false }
        return await saveSettings(name: summary.name, planType: summary.planType, customCarbPct: summary.customCarbPct,
                                  mode: .advanced, confirmReset: false)
    }

    /// Returns an advanced plan to easy. Every day's own target is dropped,
    /// so the caller asks the person first; `planType` must be a preset.
    @discardableResult
    func switchToEasy(planType: MealPlanType) async -> Bool {
        guard let name = plan?.value1.name else { return false }
        return await saveSettings(name: name, planType: planType, customCarbPct: nil, mode: .easy, confirmReset: true)
    }

    private func saveSettings(name: String, planType: MealPlanType, customCarbPct: Double?, mode: MealPlanMode, confirmReset: Bool) async -> Bool {
        let description = plan?.value1.description
        return await write { confirm in
            try await self.service.updatePlan(self.id, MealPlanUpdate(
                name: name, description: description, planType: planType, customCarbPct: customCarbPct,
                mode: mode, confirmReset: confirmReset, confirmOverage: confirm
            ))
        }
    }

    /// Sends a change, and on an overage keeps it so the person can confirm.
    private func write<Saved>(_ send: @escaping @MainActor (Bool) async throws -> PlanWrite<Saved>) async -> Bool {
        do {
            switch try await send(false) {
            case .saved:
                await load()
                return true
            case .over(let overage):
                pendingOverage = PendingOverage(overage: overage) { [weak self] in
                    guard let self else { return }
                    self.pendingOverage = nil
                    do {
                        if case .over(let again) = try await send(true) {
                            self.pendingOverage = PendingOverage(overage: again) {}
                        }
                        await self.load()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    // MARK: Changes that cannot go over

    func addDay(weekday: Int?) async {
        await run { self.plan = try await self.service.addDay(to: self.id, weekday: weekday) }
    }

    func removeDay(_ dayID: String) async {
        await run { try await self.service.removeDay(dayID); await self.load() }
    }

    func addMeal(to dayID: String, name: String) async {
        await run { self.plan = try await self.service.addMeal(to: dayID, name: name) }
    }

    func removeMeal(_ mealID: String) async {
        await run { try await self.service.removeMeal(mealID); await self.load() }
    }

    func removePortion(_ portionID: String) async {
        await run { try await self.service.removePortion(portionID); await self.load() }
    }

    private func run(_ action: @MainActor () async throws -> Void) async {
        do { try await action(); error = nil } catch { self.error = error.localizedDescription }
    }

    // MARK: Reading a day

    func day(_ dayID: String) -> MealPlanDay? { days.first { $0.id == dayID } }

    /// The day a meal counts toward. Nil for an alternative option: it is
    /// eaten instead of its slot's first option, so it never moves the day.
    func day(holding mealID: String) -> MealPlanDay? { days.first { $0.meals.contains { $0.id == mealID } } }

    /// True when the id is one of a slot's other options rather than a
    /// slot's counted first option.
    func isAlternative(_ mealID: String) -> Bool {
        days.contains { $0.meals.contains { ($0.alternatives ?? []).contains { $0.id == mealID } } }
    }

    /// What a day would have left after a portion still being chosen: the
    /// server's remaining, less the portion's share of its per-100 g macros.
    /// Nil without a target.
    func remaining(on dayID: String, after per100g: Macros? = nil, grams: Double = 0) -> Macros? {
        guard let left = day(dayID)?.status?.remaining else { return nil }
        guard let per100g else { return left }
        let share = grams / 100
        return Macros(
            calories: left.calories - per100g.calories * share,
            proteinG: left.proteinG - per100g.proteinG * share,
            fatG: left.fatG - per100g.fatG * share,
            carbG: left.carbG - per100g.carbG * share
        )
    }
}

extension MealPlanDay {
    /// The day's name in the person's language; 0 is Sunday on both sides.
    var name: String { Calendar.current.standaloneWeekdaySymbols[weekday] }
}

/// One option of a meal slot: the slot's first, the one its day counts, or
/// one of the alternatives eaten instead of it. Each is its own meal on the
/// server, so its id is what portions, removal and logging act on.
struct PlanMealOption: Identifiable, Hashable {
    let id: String
    let label: String
    let isCounted: Bool
    let totalMacros: Macros
    let ingredients: [MealPortion]
}

extension MealPlanMeal {
    var hasAlternatives: Bool { !(alternatives ?? []).isEmpty }

    /// The slot's options in order: itself first, then its alternatives. An
    /// option without a label is named by its place, as the server names it.
    var options: [PlanMealOption] {
        let first = PlanMealOption(id: id, label: Self.label(optionLabel, place: 1), isCounted: true,
                                   totalMacros: totalMacros, ingredients: ingredients)
        let others = (alternatives ?? []).enumerated().map { index, option in
            PlanMealOption(id: option.id, label: Self.label(option.optionLabel, place: index + 2), isCounted: false,
                           totalMacros: option.totalMacros, ingredients: option.ingredients)
        }
        return [first] + others
    }

    private static func label(_ label: String?, place: Int) -> String {
        let label = label?.trimmingCharacters(in: .whitespaces) ?? ""
        return label.isEmpty ? "Option \(place)" : label
    }
}

/// A plan meal the log sheet offers: one row per option, logged by its id.
struct LoggableMeal: Identifiable, Hashable {
    let id: String
    let title: String
    let calories: Double
}

extension MealPlanDetail {
    /// Every option of today's meals, in plan order, as the web offers them.
    /// `today` counts as the API does, 0 for Sunday. A plan with no day for
    /// today offers all its days, each title naming its weekday; otherwise
    /// the weekday goes without saying. A slot with alternatives names each
    /// option ("Lunch · Option 2"); one without stays "Lunch".
    func loggableMeals(today: Int) -> [LoggableMeal] {
        let todays = value2.days.filter { $0.weekday == today }
        let days = todays.isEmpty ? value2.days : todays
        return days.flatMap { day in
            let prefix = todays.isEmpty ? "\(value1.name) · \(day.name)" : value1.name
            return day.meals.flatMap { meal in
                let title = "\(prefix) · \(meal.name)"
                guard meal.hasAlternatives else {
                    return [LoggableMeal(id: meal.id, title: title, calories: meal.totalMacros.calories)]
                }
                return meal.options.map {
                    LoggableMeal(id: $0.id, title: "\(title) · \($0.label)", calories: $0.totalMacros.calories)
                }
            }
        }
    }
}
