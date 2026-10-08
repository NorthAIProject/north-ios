import NorthAPI
import SwiftUI

/// A meal draft being reviewed, with stable identities for its rows.
///
/// The server recomputes the whole draft on every preview. Rows keep their
/// identity by position across those refreshes, so a list does not rebuild
/// itself — and drop the keyboard — every time a total changes.
struct EditableMealDraft {
    var settings: MealImportDraft
    var days: [Day]

    struct Day: Identifiable {
        let id: UUID
        var value: MealImportDay
        var meals: [Meal]
    }

    struct Meal: Identifiable {
        let id: UUID
        var name: String
        var foods: [Food]
    }

    struct Food: Identifiable {
        let id: UUID
        var value: MealImportFood
    }

    init(_ draft: MealImportDraft, keeping previous: EditableMealDraft? = nil) {
        settings = draft
        days = draft.days.enumerated().map { dayIndex, day in
            let oldDay = previous?.days[safe: dayIndex]
            return Day(
                id: oldDay?.id ?? UUID(),
                value: day,
                meals: day.meals.enumerated().map { mealIndex, meal in
                    let oldMeal = oldDay?.meals[safe: mealIndex]
                    return Meal(
                        id: oldMeal?.id ?? UUID(),
                        name: meal.name,
                        foods: meal.foods.enumerated().map { foodIndex, food in
                            Food(id: oldMeal?.foods[safe: foodIndex]?.id ?? UUID(), value: food)
                        }
                    )
                }
            )
        }
    }

    var draft: MealImportDraft {
        var out = settings
        out.days = days.map { day in
            var value = day.value
            value.meals = day.meals.map { MealImportMeal(name: $0.name, foods: $0.foods.map(\.value)) }
            return value
        }
        return out
    }

    var isAdvanced: Bool { settings.mode == MealPlanMode.advanced.rawValue }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension ImportMacros {
    /// "30 P · 54 C · 6 F", rounded to whole grams.
    var summary: String {
        "\(Int(proteinG.rounded())) P · \(Int(carbG.rounded())) C · \(Int(fatG.rounded())) F"
    }
}
