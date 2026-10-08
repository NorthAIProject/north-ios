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

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($draft) {
                    MealImportReview(draft: binding, error: error) { Task { await preview() } }
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
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(working).font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
                }
            }
            .interactiveDismissDisabled(working != nil || draft != nil)
        }
    }

    private var start: some View {
        Form {
            Section {
                Button("Choose File or Photo", systemImage: "doc.badge.plus") { picking = true }
            } footer: {
                Text("""
                    A spreadsheet needs a header row: day, meal, food, quantity, unit, protein, carbs, fat. \\
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

    private func preview() async {
        guard let current = draft else { return }
        do {
            draft = EditableMealDraft(try await service.previewMeal(current.draft), keeping: current)
            error = nil
        } catch {
            self.error = error.importMessage
        }
    }

    private func save(confirm: Bool) async {
        guard let current = draft else { return }
        working = "Saving…"
        defer { working = nil }
        do {
            switch try await service.commitMeal(current.draft, confirm: confirm) {
            case .saved(let id):
                onSaved(id)
                dismiss()
            case .over(let over):
                overage = over
                await preview()
            }
        } catch {
            self.error = error.importMessage
            await preview()
        }
    }
}

extension Error {
    /// The server's own sentence for a refused file or draft ("This PDF is
    /// password-protected…") rather than the generic summary.
    var importMessage: String {
        if let api = self as? APIError, case .fieldValidation(let message, let fields) = api {
            return fields["file"] ?? fields["plan"] ?? message
        }
        return localizedDescription
    }
}

/// The meal draft as editable rows. Changes that move a total — a weekday, an
/// ingredient, a weight, a deletion, the plan's settings — ask the server to
/// recompute; typing a name does not.
struct MealImportReview: View {
    @Binding var draft: EditableMealDraft
    let error: String?
    let recompute: () -> Void

    var body: some View {
        Form {
            settingsSection
            if let error { ErrorRow(error) }
            ForEach($draft.days) { $day in
                MealImportDaySection(day: $day, advanced: draft.isAdvanced, recompute: recompute) {
                    draft.days.removeAll { $0.id == day.id }
                    recompute()
                }
            }
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

    private var settingsSection: some View {
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
                TextField("Carbs, % of target", value: $draft.settings.customCarbPct, format: .number)
                    .keyboardType(.decimalPad)
                    .onSubmit(recompute)
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

private struct MealImportDaySection: View {
    @Binding var day: EditableMealDraft.Day
    let advanced: Bool
    let recompute: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Section {
            if advanced {
                Picker("Day of the week", selection: $day.value.weekday) {
                    Text("Choose…").tag(Int?.none)
                    ForEach(MealPlanDay.mondayFirst, id: \.self) { weekday in
                        Text(Calendar.current.standaloneWeekdaySymbols[weekday]).tag(Int?.some(weekday))
                    }
                }
                .foregroundStyle(day.value.weekday == nil ? .red : .primary)
                .onChange(of: day.value.weekday) { recompute() }
            }
            DayTotals(day: day.value)
            ForEach($day.meals) { $meal in
                TextField("Meal name", text: $meal.name).font(.headline)
                ForEach($meal.foods) { $food in
                    MealImportFoodRow(food: $food.value, recompute: recompute)
                }
                .onDelete { offsets in
                    meal.foods.remove(atOffsets: offsets)
                    day.meals.removeAll { $0.foods.isEmpty }
                    recompute()
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button("Remove Day", role: .destructive, action: onRemove).font(.caption)
            }
        }
    }

    private var title: String {
        let label = day.value.label.isEmpty ? "Day" : day.value.label
        guard !advanced, let weekday = day.value.weekday else { return label }
        return "\(label) · \(Calendar.current.standaloneWeekdaySymbols[weekday])"
    }
}

private struct DayTotals: View {
    let day: MealImportDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total \(line(day.totals))")
            if let target = day.target {
                Text("Target \(line(target)) · left \(line(day.remaining))")
            }
            ForEach(day.over ?? [], id: \.self) { Text($0).foregroundStyle(.red) }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func line(_ macros: ImportMacros?) -> String {
        macros?.summary ?? "—"
    }
}

private struct MealImportFoodRow: View {
    @Binding var food: MealImportFood
    let recompute: () -> Void

    private static let mine = "mine"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(food.food)
            Text(source).font(.caption).foregroundStyle(.secondary)
            Picker("Ingredient", selection: ingredient) {
                Text("Choose…").tag("")
                ForEach(food.candidates ?? [], id: \.id) { Text($0.name).tag($0.id) }
                if let id = food.ingredientId, !(food.candidates ?? []).contains(where: { $0.id == id }) {
                    Text(food.matchedName).tag(id)
                }
                if hasStatedMacros { Text("My own food (file's macros)").tag(Self.mine) }
            }
            HStack {
                Text("Grams")
                TextField("—", value: $food.grams, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(recompute)
            }
            if let macros = food.macros {
                Text(macros.summary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(food.flags ?? [], id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            ForEach(food.checks ?? [], id: \.self) { check in
                Label(check, systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var hasStatedMacros: Bool {
        food.statedProteinG != nil && food.statedCarbG != nil && food.statedFatG != nil
    }

    private var source: String {
        var parts: [String] = []
        if let quantity = food.quantity { parts.append("\(quantity.formatted()) \(food.unit)") }
        if let protein = food.statedProteinG, let carbs = food.statedCarbG, let fat = food.statedFatG {
            parts.append("file says \(Int(protein)) P · \(Int(carbs)) C · \(Int(fat)) F")
        }
        return parts.isEmpty ? "From your file" : parts.joined(separator: " · ")
    }

    private var ingredient: Binding<String> {
        Binding(
            get: { food.saveAsMine ? Self.mine : (food.ingredientId ?? "") },
            set: { choice in
                food.saveAsMine = choice == Self.mine
                food.ingredientId = (choice.isEmpty || choice == Self.mine) ? nil : choice
                recompute()
            }
        )
    }
}
