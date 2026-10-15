import NorthAPI
import SwiftUI

/// One imported training day: its weekday, its exercises, and a way to drop it.
struct WorkoutImportDaySection: View {
    @Binding var day: EditableWorkoutDraft.Day
    /// Another day already has this weekday, so saving is refused until one changes.
    let isRepeatedWeekday: Bool
    let onRemove: () -> Void
    @Environment(\.calendar) private var calendar

    var body: some View {
        Section {
            Picker("Day of the week", selection: $day.weekday) {
                Text("Choose…").tag("")
                ForEach(EditableWorkoutDraft.weekdays, id: \.self) { Text(weekdayName($0)).tag($0) }
            }
            .foregroundStyle(day.weekday.isEmpty || isRepeatedWeekday ? .red : .primary)

            ForEach($day.exercises) { $item in
                WorkoutImportExerciseRow(exercise: $item.exercise)
            }
            .onDelete { day.exercises.remove(atOffsets: $0) }

            Button("Remove Day", systemImage: "trash", role: .destructive, action: onRemove)
        } header: {
            if day.label.isEmpty { Text("Training day") } else { Text(day.label) }
        } footer: {
            if isRepeatedWeekday {
                Text("Another day is also on \(weekdayName(day.weekday)). Give each day its own.")
                    .foregroundStyle(.red)
            }
        }
    }

    /// The weekday in the reader's language. The English name stays the
    /// value sent to the server.
    private func weekdayName(_ day: String) -> String {
        guard let index = EditableWorkoutDraft.weekdays.firstIndex(of: day) else { return day }
        return calendar.standaloneWeekdaySymbols[(index + 1) % 7]
    }
}
