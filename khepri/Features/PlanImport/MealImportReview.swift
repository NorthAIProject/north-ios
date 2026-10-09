import NorthAPI
import SwiftUI

/// The meal draft as editable rows. Changes that move a total — a weekday, an
/// ingredient, a weight, a deletion, the plan's settings — ask the server to
/// recompute; typing a name does not.
struct MealImportReview: View {
    @Binding var draft: EditableMealDraft
    let error: String?
    let recompute: () -> Void

    var body: some View {
        Form {
            MealImportSettingsSection(draft: $draft, recompute: recompute)
            if let error { ErrorRow(error) }
            ForEach($draft.days) { $day in
                MealImportDaySection(
                    day: $day, advanced: draft.isAdvanced, everyDay: draft.isEveryDay, recompute: recompute
                ) {
                    draft.days.removeAll { $0.id == day.id }
                    recompute()
                }
            }
            if let notes = draft.notes { PlanNotesSection(notes: notes) }
            if !draft.settings.unparsed.isEmpty {
                Section {
                    ForEach(draft.settings.unparsed, id: \.self) { Text("“\($0)”").font(.footnote) }
                } header: {
                    Text("Not imported")
                } footer: {
                    Text("These lines looked like part of the plan but couldn't be read as foods.")
                }
            }
        }
    }
}
