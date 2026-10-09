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

    /// A meal slot. `foods` is its first option, the one its day counts;
    /// `alternatives` are eaten instead of it. `value` keeps everything else
    /// the server sent — the first option's label among it — so it goes back
    /// unchanged.
    struct Meal: Identifiable {
        let id: UUID
        var value: MealImportMeal
        var foods: [Food]
        var alternatives: [Option]

        var name: String {
            get { value.name }
            set { value.name = newValue }
        }

        /// Nothing left in any option: the slot is gone.
        var isEmpty: Bool { foods.isEmpty && alternatives.isEmpty }

        /// "Opção 1" as the file said it, or "Option 1".
        var firstOptionTitle: String { Self.title(value.optionLabel, place: 1) }

        /// An alternative's label as the file said it, or "Option N" by its
        /// place, as saving names it.
        func title(of alternativeID: Option.ID) -> String {
            let index = alternatives.firstIndex { $0.id == alternativeID } ?? 0
            return Self.title(alternatives[safe: index]?.value.label, place: index + 2)
        }

        /// Removes foods from the first option, or from the alternative given.
        /// An alternative left empty goes; a first option left empty is
        /// replaced by the next one, as saving would do, so the day's total
        /// shows what will be counted.
        mutating func removeFoods(atOffsets offsets: IndexSet, fromAlternative alternativeID: Option.ID? = nil) {
            if let alternativeID, let index = alternatives.firstIndex(where: { $0.id == alternativeID }) {
                alternatives[index].foods.remove(atOffsets: offsets)
                if alternatives[index].foods.isEmpty { alternatives.remove(at: index) }
                return
            }
            foods.remove(atOffsets: offsets)
            guard foods.isEmpty, !alternatives.isEmpty else { return }
            let next = alternatives.removeFirst()
            foods = next.foods
            value.optionLabel = next.value.label.isEmpty ? nil : next.value.label
        }

        private static func title(_ label: String?, place: Int) -> String {
            let label = label?.trimmingCharacters(in: .whitespaces) ?? ""
            return label.isEmpty ? "Option \(place)" : label
        }
    }

    /// One of a meal's other options, with the label the file gave it.
    struct Option: Identifiable {
        let id: UUID
        var value: MealImportOption
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
                        value: meal,
                        foods: Self.foods(meal.foods, keeping: oldMeal?.foods),
                        alternatives: (meal.alternatives ?? []).enumerated().map { optionIndex, option in
                            let oldOption = oldMeal?.alternatives[safe: optionIndex]
                            return Option(
                                id: oldOption?.id ?? UUID(),
                                value: option,
                                foods: Self.foods(option.foods, keeping: oldOption?.foods)
                            )
                        }
                    )
                }
            )
        }
    }

    private static func foods(_ foods: [MealImportFood], keeping previous: [Food]?) -> [Food] {
        foods.enumerated().map { index, food in Food(id: previous?[safe: index]?.id ?? UUID(), value: food) }
    }

    /// The draft in the server's shape. Every field the server sent comes
    /// back as it was — every-day, notes, option labels, each food's source
    /// line and estimate — with the person's edits on top.
    var draft: MealImportDraft {
        var out = settings
        out.days = days.map { day in
            var value = day.value
            value.meals = day.meals.map { meal in
                var value = meal.value
                value.foods = meal.foods.map(\.value)
                // Absent stays absent: a meal the server sent without
                // alternatives goes back without them.
                value.alternatives = meal.value.alternatives == nil && meal.alternatives.isEmpty ? nil
                    : meal.alternatives.map { option in
                        var value = option.value
                        value.foods = option.foods.map(\.value)
                        return value
                    }
                return value
            }
            return value
        }
        return out
    }

    var isEveryDay: Bool { settings.everyDay == true }

    /// The last day stays: nothing in the sheet adds one back, and the
    /// server refuses a draft with none.
    var canRemoveDay: Bool { days.count > 1 }

    /// The advice the file carried beside its meals; nil when blank.
    var notes: String? {
        let notes = settings.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? nil : notes
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
