import NorthAPI
import SwiftUI

/// Import a meal plan: pick a file or photo, check foods against what's left
/// of the macro target, save.
///
/// The target is only read. A day over it is refused on save exactly as it is
/// when building a plan by hand: always on an easy plan, until confirmed on an
/// advanced one.
struct MealImportSheet: View {
    var service: PlanImportServicing = PlanImportService()
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EditableMealDraft?
    @State private var picking = false
    @State private var working: String?
    @State private var error: String?
    @State private var overage: MacroOverage?
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($draft) {
                    MealImportReview(draft: binding, error: error, recompute: recompute)
                } else {
                    start
                }
            }
            .navigationTitle("Import Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working != nil)
                }
                if draft != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save(confirm: false) } }
                            .disabled(working != nil || !(draft?.settings.hasTarget ?? false))
                    }
                }
            }
            .importSourcePicker(isPresented: $picking) { file in
                Task { await read(file) }
            } onError: { message in
                error = message
            }
            .alert("Over your target", isPresented: Binding(get: { overage != nil }, set: { if !$0 { overage = nil } }),
                   presenting: overage) { over in
                if over.canConfirm {
                    Button("Save Anyway", role: .destructive) { Task { await save(confirm: true) } }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { over in
                Text(over.explanation)
            }
            .overlay {
                if let working {
                    ImportProgressOverlay(title: working)
                }
            }
            .interactiveDismissDisabled(working != nil || draft != nil)
        }
    }

    private var start: some View {
        Form {
            Section {
                Button("Choose File or Photo", systemImage: "doc.badge.plus") { picking = true }
                    .disabled(working != nil)
            } footer: {
                Text("""
                    A spreadsheet needs a header row: day, meal, food, quantity, unit, protein, carbs, fat. \
                    Foods are matched to ingredients and measured against your macro target, which doesn't change.
                    """)
            }
            if let error { ErrorRow(error) }
        }
    }

    private func read(_ file: ImportFile) async {
        working = "Reading your plan…"
        defer { working = nil }
        do {
            draft = EditableMealDraft(try await service.parseMeal(filename: file.filename, data: file.data))
            error = nil
        } catch {
            self.error = error.importMessage
        }
    }

    /// Asks the server to recompute, replacing any request still in flight:
    /// its answer would describe a draft that no longer exists.
    private func recompute() {
        previewTask?.cancel()
        previewTask = Task { await preview() }
    }

    /// Applies the server's recomputed draft only if nothing was edited while
    /// it was asked; otherwise asks again for what is on screen now, so an
    /// edit made mid-request is neither overwritten nor left uncounted.
    private func preview() async {
        while let sent = draft?.draft, !Task.isCancelled {
            do {
                let result = try await service.previewMeal(sent)
                guard !Task.isCancelled else { return }
                guard let latest = draft, latest.draft == sent else { continue }
                draft = EditableMealDraft(result, keeping: latest)
                error = nil
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.importMessage
                return
            }
        }
    }

    private func save(confirm: Bool) async {
        guard let current = draft else { return }
        previewTask?.cancel()
        working = "Saving…"
        defer { working = nil }
        do {
            switch try await service.commitMeal(current.draft, confirm: confirm) {
            case .saved(let id):
                onSaved(id)
                dismiss()
            case .over(let over):
                overage = over
                recompute()
            }
        } catch {
            // The refresh clears the error when it succeeds, so the save's
            // reason is set after it, not before.
            let message = error.importMessage
            recompute()
            await previewTask?.value
            self.error = message
        }
    }
}
