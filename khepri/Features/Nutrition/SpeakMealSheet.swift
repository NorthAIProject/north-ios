import NorthAPI
import SwiftUI

/// A meal read out of one sentence: what was heard, which ingredient each
/// portion probably is, and how much of it.
///
/// Nothing is added until the person taps Add. The server reads the sentence
/// and offers ingredients; it writes nothing, so a misheard "300" is caught
/// here by the one person who knows they said "30".
@MainActor @Observable
final class SpeakMealModel {
    struct Row: Identifiable {
        let id: Int
        let source: String
        let query: String
        let uncertain: Bool
        let candidates: [Components.Schemas.FoodCandidate]
        let problem: String?
        /// Set only when exactly one ingredient answered to the name, until
        /// the person picks one.
        var ingredientID: String?
        var grams: Double
        var included: Bool

        init(index: Int, line: FoodLine) {
            id = index
            source = line.source
            query = line.query
            uncertain = line.uncertain ?? false
            candidates = line.candidates
            problem = line.problem
            ingredientID = line.ingredientId
            grams = min(max(line.grams, SpeakMealModel.grams.lowerBound), SpeakMealModel.grams.upperBound)
            included = line.ingredientId != nil
        }
    }

    /// The server's own bounds for one portion.
    static let grams: ClosedRange<Double> = 1...5000

    var text = ""
    var rows: [Row] = []
    private(set) var unparsed: [String] = []
    private(set) var parsed = false
    private(set) var busy = false
    var error: String?

    private let parse: (String) async throws -> FoodDraft

    init(parse: @escaping (String) async throws -> FoodDraft) {
        self.parse = parse
    }

    var canFind: Bool { !busy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The rows Add will send: ticked, with an ingredient chosen.
    var kept: [Row] { rows.filter { $0.included && $0.ingredientID != nil } }

    func find() async {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let draft = try await parse(sentence)
            rows = draft.lines.enumerated().map { Row(index: $0.offset, line: $0.element) }
            unparsed = draft.unparsed
            parsed = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sends the kept rows as one batch, which the server adds together or
    /// not at all, and reports whether it went in. A refused batch leaves
    /// every row showing, so Add can simply be tapped again.
    func add(using onAdd: ([(ingredientID: String, grams: Double)]) async -> Bool) async -> Bool {
        busy = true
        defer { busy = false }
        let portions = kept.compactMap { row in row.ingredientID.map { (ingredientID: $0, grams: row.grams) } }
        return await onAdd(portions)
    }
}

struct SpeakMealSheet: View {
    let store: MealPlanStore
    let mealID: String
    @State private var model: SpeakMealModel
    @Environment(\.dismiss) private var dismiss

    init(store: MealPlanStore, service: NutritionServicing, mealID: String) {
        self.store = store
        self.mealID = mealID
        _model = State(initialValue: SpeakMealModel(parse: service.parseFoods))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top) {
                        TextField("200 g chicken breast, 100 g rice and two eggs", text: $model.text, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("speak-meal-text")
                        DictationButton(text: $model.text, font: .body)
                    }
                    Button("Find Ingredients") { Task { await model.find() } }
                        .disabled(!model.canFind)
                } footer: {
                    Text("Say each food and how much. You check everything before it's added.")
                }
                if let error = model.error ?? store.error { ErrorRow(error) }
                if model.parsed && model.rows.isEmpty && model.error == nil {
                    Section { Text("No food found in that. Name each food and how much, like “150 g salmon”.") }
                }
                ForEach($model.rows) { $row in
                    Section { SpokenPortionRow(row: $row) }
                }
                if !model.unparsed.isEmpty {
                    Section("Not added") {
                        ForEach(model.unparsed, id: \.self) { Text("“\($0)”").foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Say a Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(model.kept.count)") {
                        Task { if await model.add(using: { await store.addPortions(to: mealID, $0) }) { dismiss() } }
                    }
                    .disabled(model.kept.isEmpty || model.busy)
                }
            }
            .overlay { if model.busy { ProgressView() } }
            .overagePrompt(store, active: true) { dismiss() }
        }
    }
}

private struct SpokenPortionRow: View {
    @Binding var row: SpeakMealModel.Row

    var body: some View {
        if row.candidates.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(row.grams)) g \(row.query)")
                if let problem = row.problem { Text(problem).font(.footnote).foregroundStyle(.red) }
            }
        } else {
            Toggle(isOn: $row.included) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(row.source)”").font(.footnote).foregroundStyle(.secondary)
                    if row.uncertain {
                        Label("Amount estimated", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .disabled(row.ingredientID == nil)
            Picker("Ingredient", selection: $row.ingredientID) {
                if row.ingredientID == nil { Text("Choose which \(row.query)").tag(String?.none) }
                ForEach(row.candidates, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            // Choosing between two rices is the person saying which one they
            // ate, so the choice ticks the row.
            .onChange(of: row.ingredientID) { _, picked in if picked != nil { row.included = true } }
            Stepper("\(Int(row.grams)) g", value: $row.grams, in: SpeakMealModel.grams, step: 5)
        }
    }
}
