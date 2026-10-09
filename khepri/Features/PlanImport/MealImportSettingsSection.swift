import NorthAPI
import SwiftUI

/// The imported plan's name, mode and carb type, chosen as for a new plan.
struct MealImportSettingsSection: View {
    @Binding var draft: EditableMealDraft
    let recompute: () -> Void

    var body: some View {
        Section {
            TextField("Plan name", text: $draft.settings.name)
            Picker("Mode", selection: $draft.settings.mode) {
                Text(MealPlanMode.easy.title).tag(MealPlanMode.easy.rawValue)
                Text(MealPlanMode.advanced.title).tag(MealPlanMode.advanced.rawValue)
            }
            .onChange(of: draft.settings.mode) { recompute() }
            Picker("Carb type", selection: $draft.settings.planType) {
                Text("Choose…").tag("")
                ForEach(MealPlanType.presets, id: \.self) { Text($0.title).tag($0.rawValue) }
                if draft.isAdvanced { Text(MealPlanType.custom.title).tag(MealPlanType.custom.rawValue) }
            }
            .onChange(of: draft.settings.planType) { recompute() }
            if draft.settings.planType == MealPlanType.custom.rawValue {
                // The decimal pad has no Return key, so the committed value,
                // not a submit, is what asks for a recompute.
                TextField("Carbs, % of target", value: $draft.settings.customCarbPct, format: .number)
                    .keyboardType(.decimalPad)
                    .onChange(of: draft.settings.customCarbPct) { recompute() }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.isAdvanced
                     ? "Advanced: pick each day's weekday; a day over its target can be saved once you confirm."
                     : "Easy: days run from Monday in order, and no day may go over its target.")
                if !draft.settings.hasTarget {
                    Text("You have no macro target yet. Work it out in Body & Goal first; meal plans are built on it.")
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
