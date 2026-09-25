import NorthAPI
import NorthKit
import SwiftUI

typealias Decision = Components.Schemas.Decision
typealias DecisionInput = Components.Schemas.DecisionInput

protocol DecisionsServicing: Sendable {
    func decisions() async throws -> [Decision]
    func create(_ input: DecisionInput) async throws
    func update(_ id: String, _ input: DecisionInput) async throws
    func delete(_ id: String) async throws
}

struct DecisionsService: DecisionsServicing {
    var api: Client = API.shared

    func decisions() async throws -> [Decision] {
        try await NorthAPI.call { try await api.listDecisions().ok.body.json.decisions }
    }
    func create(_ input: DecisionInput) async throws {
        try await NorthAPI.call { _ = try await api.createDecision(body: .json(input)).created }
    }
    func update(_ id: String, _ input: DecisionInput) async throws {
        try await NorthAPI.call { _ = try await api.updateDecision(path: .init(decisionID: id), body: .json(input)).ok }
    }
    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteDecision(path: .init(decisionID: id)).noContent }
    }
}

/// A log of decisions: what was chosen between, why, and, later, how it
/// turned out. The coach reads it when a similar choice comes up.
struct DecisionsScreen: View {
    var service: DecisionsServicing = DecisionsService()
    @State private var decisions: [Decision] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: Decision?
    @State private var creating = false

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if loaded, decisions.isEmpty {
                Text("Write down a decision as you make it. Coming back to how it turned out is where the learning is.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(decisions, id: \.id) { decision in
                Button { editing = decision } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(decision.title).font(.headline).foregroundStyle(.primary)
                        Text(decision.outcome.isEmpty ? "How did it turn out? Tap to add." : decision.outcome)
                            .font(.subheadline)
                            .foregroundStyle(decision.outcome.isEmpty ? NorthColor.signal : .secondary)
                            .lineLimit(2)
                        Text(decision.decidedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { try await service.delete(decision.id); await load() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
        }
        .navigationTitle("Decisions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("New Decision", systemImage: "plus") { creating = true } }
        }
        .sheet(isPresented: $creating) {
            DecisionForm(title: "New Decision", input: .init(title: "", options: "", rationale: "", outcome: "")) { input in
                try await service.create(input)
                await load()
            }
        }
        .sheet(item: $editing) { decision in
            DecisionForm(title: "Decision", input: .init(title: decision.title, options: decision.options,
                                                        rationale: decision.rationale, outcome: decision.outcome)) { input in
                try await service.update(decision.id, input)
                await load()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { decisions = try await service.decisions(); error = nil } catch { self.error = error.localizedDescription }
        loaded = true
    }
}

extension Decision: Identifiable {}

private struct DecisionForm: View {
    let title: String
    @State var input: DecisionInput
    let onSave: (DecisionInput) async throws -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you deciding?", text: $input.title, axis: .vertical)
                Section("The options") {
                    TextField("What you're choosing between", text: Binding($input.options, default: ""), axis: .vertical)
                }
                Section("Why") {
                    TextField("What tipped it", text: Binding($input.rationale, default: ""), axis: .vertical)
                }
                Section("How it turned out") {
                    TextField("Come back and fill this in", text: Binding($input.outcome, default: ""), axis: .vertical)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do { try await onSave(input); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(input.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension Binding where Value == String {
    /// A binding to an optional string, reading nil as a default.
    init(_ source: Binding<String?>, default fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0 })
    }
}
