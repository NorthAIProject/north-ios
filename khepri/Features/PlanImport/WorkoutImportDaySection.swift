import NorthAPI
import SwiftUI

/// One imported training day: its weekday, its exercises, and a way to drop it.
struct WorkoutImportDaySection: View {
    @Binding var day: EditableWorkoutDraft.Day
    /// Another day already has this weekday, so saving is refused until one changes.
    let isRepeatedWeekday: Bool
    let onRemove: () -> Void

    var body: some View {
        Section {
            Picker("Day of the week", selection: $day.weekday) {
                Text("Choose…").tag("")
                ForEach(EditableWorkoutDraft.weekdays, id: \.self) { Text($0).tag($0) }
            }
            .foregroundStyle(day.weekday.isEmpty || isRepeatedWeekday ? .red : .primary)

            ForEach($day.exercises) { $item in
                WorkoutImportExerciseRow(exercise: $item.exercise)
            }
            .onDelete { day.exercises.remove(atOffsets: $0) }

            Button("Remove Day", systemImage: "trash", role: .destructive, action: onRemove)
        } header: {
            Text(day.label.isEmpty ? "Training day" : day.label)
        } footer: {
            if isRepeatedWeekday {
                Text("Another day is also on \(day.weekday). Give each day its own.")
                    .foregroundStyle(.red)
            }
        }
    }
}
