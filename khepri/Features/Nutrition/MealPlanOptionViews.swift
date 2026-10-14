import NorthAPI
import SwiftUI

/// A slot's alternatives under its counted first option, collapsed until
/// asked for. Each acts on its own meal id: its portions, its ingredients,
/// and removing it alone.
struct MealAlternativesGroup: View {
    let meal: MealPlanMeal
    let canAdd: Bool
    let onAdd: (String) -> Void
    let onSpeak: (String) -> Void
    let onRemoveOption: (String) -> Void
    let onRemovePortion: (String) -> Void
    let onToggleOptional: (MealPortion) -> Void

    var body: some View {
        let alternatives = meal.options.dropFirst()
        DisclosureGroup(alternatives.count == 1 ? "1 other option" : "\(alternatives.count) other options") {
            ForEach(alternatives) { option in
                HStack {
                    Text(option.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(option.totalMacros.calories)) kcal").foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Eaten instead of the first option; not counted in the day")
                .swipeActions {
                    Button("Remove Option", role: .destructive) { onRemoveOption(option.id) }
                }
                ForEach(option.ingredients, id: \.id) { portion in
                    PlanPortionRow(
                        portion: portion,
                        onRemove: { onRemovePortion(portion.id) },
                        onToggleOptional: { onToggleOptional(portion) }
                    )
                }
                if canAdd {
                    MealActionsRow(onAdd: { onAdd(option.id) }, onSpeak: { onSpeak(option.id) })
                }
            }
        }
    }
}

/// One portion of a plan meal: its weight and calories, what an imported plan
/// said for it, whether that weight was a guess, and whether the plan only
/// offers it (optional: shown, not counted in the meal or day).
struct PlanPortionRow: View {
    let portion: MealPortion
    let onRemove: () -> Void
    let onToggleOptional: () -> Void

    private var isOptional: Bool { portion.optional == true }

    var body: some View {
        LabeledContent {
            Text("\(Int(portion.macros.calories)) kcal")
        } label: {
            Text("\(portion.name) · \(Int(portion.quantityGrams)) g")
            if let source = portion.sourceText, !source.isEmpty { Text(source) }
            if portion.estimated == true {
                Text("≈ estimated")
                    .font(.caption)
                    .accessibilityLabel("estimated weight")
            }
            if isOptional {
                Text("Optional · not counted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 12)
        .swipeActions {
            Button("Remove", role: .destructive, action: onRemove)
        }
        .swipeActions(edge: .leading) {
            Button(isOptional ? "Count It" : "Optional", action: onToggleOptional)
                .tint(.indigo)
        }
        .accessibilityAction(named: isOptional ? "Count it" : "Make optional", onToggleOptional)
    }
}

/// Adding ingredients to one meal option, by search or by voice.
struct MealActionsRow: View {
    let onAdd: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Add Ingredient", systemImage: "plus", action: onAdd)
                .frame(minHeight: 44)
                .contentShape(.rect)
            Button("Say Ingredients", systemImage: "mic", action: onSpeak)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .padding(.leading, 12)
    }
}

/// The advice, recipes and guidance an imported plan carried beside its
/// meals, folded away until opened. Selectable, so it can be copied.
struct PlanNotesSection: View {
    let notes: String
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup("From your plan", isExpanded: $expanded) {
                Text(notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
