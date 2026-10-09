import NorthAPI
import SwiftUI

/// One imported day: its weekday (advanced plans), totals against target, and
/// the foods of each meal.
struct MealImportDaySection: View {
    @Binding var day: EditableMealDraft.Day
    let advanced: Bool
    let recompute: () -> Void
    let onRemove: () -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        Section {
            if advanced {
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
                ForEach($meal.foods) { $food in
                    MealImportFoodRow(food: $food.value, recompute: recompute)
                }
                .onDelete { offsets in
                    meal.foods.remove(atOffsets: offsets)
                    day.meals.removeAll { $0.foods.isEmpty }
                    recompute()
                }
            }
            Button("Remove Day", systemImage: "trash", role: .destructive, action: onRemove)
        } header: {
            Text(title)
        }
    }

    private var title: String {
        let label = day.value.label.isEmpty ? "Day" : day.value.label
        guard !advanced, let weekday = day.value.weekday else { return label }
        return "\(label) · \(calendar.standaloneWeekdaySymbols[weekday])"
    }
}
