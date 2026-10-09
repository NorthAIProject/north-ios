import NorthAPI
import SwiftUI

/// The draft as editable rows.
struct WorkoutImportReview: View {
    @Binding var draft: EditableWorkoutDraft
    let error: String?

    var body: some View {
        Form {
            Section {
                TextField("Plan name", text: $draft.name)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("""
                        This is what was read from your file. Blank fields weren't in it. \
                        Give each day a day of the week, fix anything wrong, then save.
                        """)
                    if draft.hasMissingSets {
                        Text("Exercises without a set count won't appear in a live workout until you add one.")
                    }
                }
            }

            if let error { ErrorRow(error) }

            let repeated = draft.repeatedWeekdays
            ForEach($draft.days) { $day in
                WorkoutImportDaySection(day: $day, isRepeatedWeekday: repeated.contains(day.weekday)) {
                    draft.days.removeAll { $0.id == day.id }
                }
            }

            if !draft.unparsed.isEmpty {
                Section {
                    ForEach(draft.unparsed, id: \.self) { Text("“\($0)”").font(.footnote) }
                } header: {
                    Text("Not imported")
                } footer: {
                    Text("These lines looked like part of the plan but couldn't be read as exercises.")
                }
            }
        }
    }
}
