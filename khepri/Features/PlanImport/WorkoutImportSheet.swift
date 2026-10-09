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
                if reading {
                    ImportProgressOverlay(
                        title: "Reading your plan…",
                        detail: "A document or photo can take up to a minute."
                    )
                } else if saving {
                    ImportProgressOverlay(title: "Saving…")
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
