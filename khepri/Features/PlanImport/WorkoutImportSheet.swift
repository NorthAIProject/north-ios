import NorthAPI
import SwiftUI

/// Import a workout plan: pick a file or photo, check what was read, save.
///
/// Nothing reaches the plan list until Save. Cancel at any point drops the
/// draft, which only ever lived here.
struct WorkoutImportSheet: View {
    var service: PlanImportServicing = PlanImportService()
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EditableWorkoutDraft?
    @State private var picking = false
    @State private var reading = false
    @State private var saving = false
    @State private var error: String?

    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($draft) {
                    WorkoutImportReview(draft: binding, error: error)
                } else {
                    start
                }
            }
            .navigationTitle("Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(reading || saving)
                }
                if draft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(saving || !(draft?.isReadyToSave ?? false))
                    }
                }
            }
            .importSourcePicker(isPresented: $picking) { file in
                Task { await read(file) }
            } onError: { message in
                error = message
            }
            .overlay {
                if reading || saving {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(reading ? "Reading your plan…" : "Saving…").font(.headline)
                        if reading {
                            Text("A document or photo can take up to a minute.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
                }
            }
            .interactiveDismissDisabled(reading || saving || draft != nil)
        }
    }

    private var start: some View {
        Form {
            Section {
                Button("Choose File or Photo", systemImage: "doc.badge.plus") { picking = true }
                    .disabled(reading)
            } footer: {
                Text("""
                    A spreadsheet needs a header row: day, exercise, sets, reps, load, rest, notes. \
                    Anything your file doesn't say is left blank for you, never guessed.
                    """)
            }
            if let error { ErrorRow(error) }
        }
    }

    private func read(_ file: ImportFile) async {
        reading = true
        defer { reading = false }
        do {
            draft = EditableWorkoutDraft(try await service.parseWorkout(filename: file.filename, data: file.data))
            error = nil
        } catch {
            self.error = error.importMessage
        }
    }

    private func save() async {
        guard let draft else { return }
        saving = true
        defer { saving = false }
        do {
            let id = try await service.commitWorkout(draft.draft)
            onSaved(id)
            dismiss()
        } catch {
            self.error = error.importMessage
        }
    }
}

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

            ForEach($draft.days) { $day in
                ImportDaySection(day: $day) {
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

private struct ImportDaySection: View {
    @Binding var day: EditableWorkoutDraft.Day
    let onRemove: () -> Void

    var body: some View {
        Section {
            Picker("Day of the week", selection: $day.weekday) {
                Text("Choose…").tag("")
                ForEach(WorkoutImportSheet.weekdays, id: \.self) { Text($0).tag($0) }
            }
            .foregroundStyle(day.weekday.isEmpty ? .red : .primary)

            ForEach($day.exercises) { $item in
                ImportExerciseRow(exercise: $item.exercise)
            }
            .onDelete { day.exercises.remove(atOffsets: $0) }
        } header: {
            HStack {
                Text(day.label.isEmpty ? "Training day" : day.label)
                Spacer()
                Button("Remove Day", role: .destructive, action: onRemove).font(.caption)
            }
        }
    }
}

private struct ImportExerciseRow: View {
    @Binding var exercise: WorkoutImportExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Exercise", text: $exercise.name).font(.headline)
            HStack {
                LabeledField(label: "Sets", text: number($exercise.sets), keyboard: .numberPad)
                LabeledField(label: "Reps", text: $exercise.reps)
                LabeledField(label: "Load", text: $exercise.load)
                LabeledField(label: "Rest s", text: number($exercise.restSeconds), keyboard: .numberPad)
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

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField("—", text: $text).keyboardType(keyboard)
        }
    }
}
