import NorthAPI
import SwiftUI

/// Save now, decide later: what was saved from the share sheet or here, with
/// the coach's suggestion for where each belongs. Nothing is filed until the
/// person says so.
struct InboxScreen: View {
    var service: InboxServicing = InboxService()
    var goals: GoalsServicing = GoalsService()
    @State private var items: [InboxItem] = []
    @State private var open = 0
    @State private var activeGoals: [GoalSummary] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var draft = ""
    @State private var choosingGoal: InboxItem?

    var body: some View {
        List {
            Section {
                TextField("A thought, a link, something that happened…", text: $draft, axis: .vertical)
                Button("Save to Inbox") { Task { await add() } }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("The coach suggests where each thing belongs. You decide.")
            }
            if let error { ErrorRow(error) }
            if loaded, items.isEmpty {
                Text("Nothing waiting.").foregroundStyle(.secondary)
            }
            ForEach(items, id: \.id) { item in
                InboxRow(item: item)
                    .swipeActions(edge: .trailing) {
                        Button("Dismiss", role: .destructive) { Task { await dismiss(item) } }
                    }
                    .contextMenu { fileMenu(item) }
                    .swipeActions(edge: .leading) {
                        if let suggestion = item.suggestion, let home = suggestion.home {
                            Button("File") { Task { await file(item, home, goalID: suggestion.goalId, title: suggestion.title) } }
                                .tint(.accentColor)
                        }
                    }
            }
        }
        .navigationTitle(open > 0 ? "Inbox (\(open))" : "Inbox")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Which goal?", isPresented: Binding(get: { choosingGoal != nil }, set: { if !$0 { choosingGoal = nil } }),
                            presenting: choosingGoal) { item in
            ForEach(activeGoals, id: \.id) { goal in
                Button(goal.title) { Task { await file(item, .goalNote, goalID: goal.id, title: nil) } }
            }
        }
    }

    @ViewBuilder
    private func fileMenu(_ item: InboxItem) -> some View {
        if let suggestion = item.suggestion, let home = suggestion.home {
            Button("File as Suggested", systemImage: "checkmark") {
                Task { await file(item, home, goalID: suggestion.goalId, title: suggestion.title) }
            }
        }
        Button("Journal", systemImage: InboxDestination.journal.systemImage) { Task { await file(item, .journal, goalID: nil, title: nil) } }
        Button("Knowledge", systemImage: InboxDestination.knowledge.systemImage) { Task { await file(item, .knowledge, goalID: nil, title: nil) } }
        if !activeGoals.isEmpty {
            Button("A Goal…", systemImage: InboxDestination.goalNote.systemImage) { choosingGoal = item }
        }
        Button("Dismiss", systemImage: "trash", role: .destructive) { Task { await dismiss(item) } }
    }

    private func load() async {
        do {
            let inbox = try await service.inbox()
            items = inbox.items
            open = inbox.open
            activeGoals = (try? await goals.goals().goals.filter { $0.status == .active }) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func add() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await service.add(text)
            draft = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func file(_ item: InboxItem, _ destination: InboxDestination, goalID: String?, title: String?) async {
        do {
            try await service.file(item.id, to: destination, goalID: goalID, title: title)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func dismiss(_ item: InboxItem) async {
        do {
            try await service.dismiss(item.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.text).lineLimit(4)
            if let suggestion = item.suggestion {
                Label(suggestion.label, systemImage: suggestion.home?.systemImage ?? "tray")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.why)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("The coach is still looking at this one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityHint("Swipe right to file as suggested, touch and hold for other places")
    }
}
