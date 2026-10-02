import NorthAPI
import NorthKit
import SwiftUI

typealias Decision = Components.Schemas.Decision
typealias DecisionInput = Components.Schemas.DecisionInput
typealias DecisionCalibration = Components.Schemas.DecisionCalibration

protocol DecisionsServicing: Sendable {
    func decisions() async throws -> [Decision]
    func decision(_ id: String) async throws -> Decision
    func create(_ input: DecisionInput) async throws
    func update(_ id: String, _ input: DecisionInput) async throws
    func delete(_ id: String) async throws
    /// How calls held up among the ones looked back on.
    func calibration() async throws -> DecisionCalibration
}

struct DecisionsService: DecisionsServicing {
    var api: Client = API.shared

    func decisions() async throws -> [Decision] {
        try await NorthAPI.call { try await api.listDecisions().ok.body.json.decisions }
    }
    func decision(_ id: String) async throws -> Decision {
        try await NorthAPI.call { try await api.getDecision(path: .init(decisionID: id)).ok.body.json }
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
    func calibration() async throws -> DecisionCalibration {
        try await NorthAPI.call { try await api.getDecisionCalibration().ok.body.json }
    }
}

/// "Did it hold?" as the server spells it: yes, partly, no, or empty for not
/// answered. Kept as a string so the form's picker and both generated enums
/// (the decision's and the input's) meet in one place.
enum DecisionHeld: String, CaseIterable, Identifiable {
    case notYet = "", yes, partly, no

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notYet: "Not yet"
        case .yes: "Yes"
        case .partly: "Partly"
        case .no: "No"
        }
    }
}

extension DecisionCalibration {
    /// "7 looked back on: 4 held, 2 partly, 1 didn't", or nil before any.
    var summary: String? {
        guard revisited > 0 else { return nil }
        return "\(revisited) looked back on: \(yes) held, \(partly) partly, \(no) didn't"
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
    @State private var calibration: DecisionCalibration?
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let summary = calibration?.summary {
                Section {
                    Label(summary, systemImage: "scope")
                        .font(.subheadline)
                }
            }
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
                                                        rationale: decision.rationale, outcome: decision.outcome,
                                                        held: decision.held.flatMap { .init(rawValue: $0.rawValue) }),
                         asksHeld: true) { input in
                try await service.update(decision.id, input)
                await load()
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // A link to one decision opens it, fetched by id so it does not wait
        // on the list.
        .task(id: router.openDecision) {
            guard let id = router.openDecision else { return }
            router.openDecision = nil
            do { editing = try await service.decision(id) } catch { self.error = error.localizedDescription }
        }
    }

    private func load() async {
        do { decisions = try await service.decisions(); error = nil } catch { self.error = error.localizedDescription }
        calibration = try? await service.calibration()
        loaded = true
    }
}

extension Decision: Identifiable {}

private struct DecisionForm: View {
    let title: String
    @State var input: DecisionInput
    /// Only an existing decision can be looked back on.
    var asksHeld = false
    let onSave: (DecisionInput) async throws -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var held: Binding<DecisionHeld> {
        Binding(
            get: { input.held.flatMap { DecisionHeld(rawValue: $0.rawValue) } ?? .notYet },
            set: { input.held = .init(rawValue: $0.rawValue) }
        )
    }

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
                if asksHeld {
                    Section("Did it hold?") {
                        Picker("Did it hold?", selection: held) {
                            ForEach(DecisionHeld.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
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
