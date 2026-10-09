import NorthAPI
import SwiftUI

/// One imported day: its weekday (advanced plans), totals against target, and
/// the foods of each meal, option by option. A plan eaten every day has one
/// day and no weekday to choose.
struct MealImportDaySection: View {
    @Binding var day: EditableMealDraft.Day
    let advanced: Bool
    var everyDay = false
    let recompute: () -> Void
    let onRemove: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        Section {
            if advanced && !everyDay {
                Picker("Day of the week", selection: $day.value.weekday) {
                    Text("Choose…").tag(Int?.none)
                    ForEach(MealPlanDay.mondayFirst, id: \.self) { weekday in
                        Text(calendar.standaloneWeekdaySymbols[weekday]).tag(Int?.some(weekday))
                    }
                }
                .foregroundStyle(day.value.weekday == nil ? .red : .primary)
                .onChange(of: day.value.weekday) { recompute() }
            }
            MealImportDayTotals(day: day.value)
            ForEach($day.meals) { $meal in
                TextField("Meal name", text: $meal.name).font(.headline)
                if !meal.alternatives.isEmpty {
                    optionHeader("\(meal.firstOptionTitle) · counted")
                }
                ForEach($meal.foods) { $food in
                    MealImportFoodRow(food: $food.value, recompute: recompute)
                }
                .onDelete { offsets in
                    meal.removeFoods(atOffsets: offsets)
                    dropEmptyMeals()
                }
                ForEach($meal.alternatives) { $option in
                    optionHeader(meal.title(of: option.id))
                    ForEach($option.foods) { $food in
                        MealImportFoodRow(food: $food.value, recompute: recompute)
                    }
                    .onDelete { offsets in
                        meal.removeFoods(atOffsets: offsets, fromAlternative: option.id)
                        dropEmptyMeals()
                    }
                }
            }
            Button("Remove Day", systemImage: "trash", role: .destructive, action: onRemove)
        } header: {
            Text(title)
        }
    }

    private func optionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func dropEmptyMeals() {
        day.meals.removeAll(where: \.isEmpty)
        recompute()
    }

    private var title: String {
        if everyDay { return "Every day" }
        let label = day.value.label.isEmpty ? "Day" : day.value.label
        guard !advanced, let weekday = day.value.weekday else { return label }
        return "\(label) · \(calendar.standaloneWeekdaySymbols[weekday])"
    }
}
