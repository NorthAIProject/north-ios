import NorthAPI
import SwiftUI

/// One imported exercise, every field editable and blank when the file was silent.
struct WorkoutImportExerciseRow: View {
    @Binding var exercise: WorkoutImportExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Exercise", text: $exercise.name).font(.headline)
            HStack {
                ImportLabeledField(label: "Sets", text: number($exercise.sets), keyboard: .numberPad)
                ImportLabeledField(label: "Reps", text: $exercise.reps)
                ImportLabeledField(label: "Load", text: $exercise.load)
                ImportLabeledField(label: "Rest s", text: number($exercise.restSeconds), keyboard: .numberPad)
            }
            TextField("Notes", text: $exercise.notes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...3)
            ForEach(exercise.flags ?? [], id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    /// An optional count as text: empty is "not stated", never zero.
    private func number(_ value: Binding<Int?>) -> Binding<String> {
        Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0.filter(\.isNumber)) }
        )
    }
}
