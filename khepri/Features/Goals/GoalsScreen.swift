import NorthAPI
import NorthKit
import SwiftUI

/// Goals: what you are working towards, with the milestones and notes that
/// show it moving. The same goals the web and the coach see.
struct GoalsScreen: View {
    var service: GoalsServicing = GoalsService()
    @State private var goals: [GoalSummary] = []
    @State private var categories: [String] = []
    @State private var loaded = false
    @State private var error: String?
    @State private var creating = false

    private var active: [GoalSummary] { goals.filter { $0.status == .active } }
    private var closed: [GoalSummary] { goals.filter { $0.status != .active } }

    var body: some View {
        content
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Goal", systemImage: "plus") { creating = true }
                }
            }
            .sheet(isPresented: $creating) {
                GoalForm(title: "New Goal", draft: GoalDraft(), categories: categories) { draft in
                    _ = try await service.create(draft)
                    await load()
                }
            }
            .task { await load() }
            .refreshable { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded, error == nil {
            ProgressView()
        } else if goals.isEmpty, error == nil {
            ContentUnavailableView {
                Label("No goals yet", systemImage: "target")
            } description: {
                Text("Name one thing you want to get done. Your coach plans around it and asks how it is going.")
            } actions: {
                Button("Add a Goal") { creating = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            List {
                if let error { ErrorRow(error) }
                if !active.isEmpty {
                    Section("Active") { ForEach(active, id: \.id, content: link) }
                }
                if !closed.isEmpty {
                    Section("Closed") { ForEach(closed, id: \.id, content: link) }
                }
            }
        }
    }

    /// A destination link, not a value link: Goals is itself pushed with one
    /// from More, and mixing the two kinds in one stack pushes screens out of
    /// order (the detail landed underneath the list).
    private func link(_ goal: GoalSummary) -> some View {
        NavigationLink {
            GoalDetailView(id: goal.id, categories: categories, service: service) { Task { await load() } }
        } label: {
            GoalRow(goal: goal)
        }
    }

    private func load() async {
        do {
            let list = try await service.goals()
            goals = list.goals
            categories = list.categories
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

private struct GoalRow: View {
    let goal: GoalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goal.title).font(.headline)
                    Spacer()
                    if goal.status != .active {
                        Text(goal.status.label.uppercased())
                            .font(.caption2.weight(.medium))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                }
                if goal.milestoneTotal > 0 {
                    ProgressView(value: Double(goal.milestoneDone), total: Double(goal.milestoneTotal))
                        .tint(NorthColor.signal)
                        .accessibilityLabel("\(goal.milestoneDone) of \(goal.milestoneTotal) milestones done")
                }
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var caption: String {
        var parts = [goal.category.capitalized]
        if goal.milestoneTotal > 0 { parts.append("\(goal.milestoneDone)/\(goal.milestoneTotal) milestones") }
        if let due = goal.targetDate.flatMap(CalendarDay.date(from:)) {
            parts.append("by " + due.formatted(.dateTime.day().month(.abbreviated).year()))
        }
        return parts.joined(separator: " · ")
    }
}

extension Components.Schemas.GoalSummary.StatusPayload {
    var label: String {
        switch self {
        case .active: "Active"
        case .achieved: "Achieved"
        case .paused: "Paused"
        case .abandoned: "Abandoned"
        }
    }
}

/// One goal: why it matters, the milestones on the way, and what moved it.
struct GoalDetailView: View {
    let id: String
    let categories: [String]
    let service: GoalsServicing
    let onChange: () -> Void

    @State private var goal: GoalDetail?
    @State private var error: String?
    @State private var newMilestone = ""
    @State private var editing = false
    @State private var noting = false
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let goal {
                content(goal)
            } else if let error {
                ContentUnavailableView("This goal did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(goal?.summary.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func content(_ goal: GoalDetail) -> some View {
        List {
            if let error { ErrorRow(error) }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.summary.title).font(.title2.weight(.semibold))
                    if !goal.motivation.isEmpty { Text(goal.motivation) }
                    if !goal.success.isEmpty {
                        Label(goal.success, systemImage: "flag.checkered")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let due = goal.summary.targetDate.flatMap(CalendarDay.date(from:)) {
                        Label("By " + due.formatted(date: .long, time: .omitted), systemImage: "calendar")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Milestones") {
                ForEach(goal.milestones, id: \.id) { milestone in
                    Button {
                        Task { await act { try await service.setMilestone(id, milestone.id, completed: milestone.status == .open) } }
                    } label: {
                        Label {
                            Text(milestone.title)
                                .strikethrough(milestone.status == .completed)
                                .foregroundStyle(milestone.status == .completed ? .secondary : .primary)
                        } icon: {
                            Image(systemName: milestone.status == .completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(NorthColor.signal)
                        }
                    }
                    .accessibilityValue(milestone.status == .completed ? "Done" : "Not done")
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await act { try await service.deleteMilestone(id, milestone.id) } }
                        }
                    }
                }
                HStack {
                    TextField("Add a milestone", text: $newMilestone)
                        .submitLabel(.done)
                        .onSubmit(addMilestone)
                    if !newMilestone.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button("Add", action: addMilestone)
                    }
                }
            }

            Section {
                Button("Add a Note", systemImage: "square.and.pencil") { noting = true }
                ForEach(goal.updates, id: \.id) { update in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(update.note)
                        HStack(spacing: 8) {
                            Text(update.createdAt.formatted(.relative(presentation: .named)))
                            if let progress = update.progress { Text("\(progress)%").monospacedDigit() }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Progress")
            } footer: {
                Text("Notes are how your coach knows a goal is moving.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Picker("Status", selection: Binding(
                        get: { goal.summary.status.rawValue },
                        set: { status in Task { await setStatus(status) } }
                    )) {
                        ForEach(Components.Schemas.GoalSummary.StatusPayload.allCases, id: \.rawValue) {
                            Text($0.label).tag($0.rawValue)
                        }
                    }
                    Button("Delete Goal", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("Goal Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) {
            GoalForm(title: "Edit Goal", draft: GoalDraft(goal: goal), categories: categories) { draft in
                self.goal = try await service.update(id, draft)
                onChange()
            }
        }
        .sheet(isPresented: $noting) {
            GoalNoteSheet { note, progress in
                try await service.addNote(id, note: note, progress: progress)
                await load()
                onChange()
            }
        }
        .confirmationDialog("Delete this goal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Goal", role: .destructive) {
                Task {
                    await act { try await service.delete(id) }
                    dismiss()
                }
            }
        } message: {
            Text("Its milestones and notes go with it.")
        }
    }

    private func load() async {
        do { goal = try await service.goal(id); error = nil } catch { self.error = error.localizedDescription }
    }

    private func act(_ action: () async throws -> Void) async {
        do { try await action(); await load(); onChange() } catch { self.error = error.localizedDescription }
    }

    private func setStatus(_ status: String) async {
        do { goal = try await service.setStatus(id, status); onChange() } catch { self.error = error.localizedDescription }
    }

    private func addMilestone() {
        let title = newMilestone.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        newMilestone = ""
        Task { await act { try await service.addMilestone(id, title: title) } }
    }
}

/// Create or edit a goal.
struct GoalForm: View {
    let title: String
    @State var draft: GoalDraft
    let categories: [String]
    let onSave: (GoalDraft) async throws -> Void

    @State private var hasDeadline = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to achieve?", text: $draft.title, axis: .vertical)
                    Picker("Area", selection: $draft.category) {
                        ForEach(categories.isEmpty ? ["personal"] : categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                Section("Why it matters") {
                    TextField("A sentence your coach can remind you of", text: $draft.motivation, axis: .vertical)
                }
                Section("How you'll know it's done") {
                    TextField("e.g. Finish under 2:10", text: $draft.success, axis: .vertical)
                }
                Section {
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("By", selection: Binding(
                            get: { draft.targetDate ?? Calendar.current.date(byAdding: .month, value: 3, to: .now)! },
                            set: { draft.targetDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hasDeadline = draft.targetDate != nil }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var draft = draft
        if !hasDeadline { draft.targetDate = nil } else if draft.targetDate == nil {
            draft.targetDate = Calendar.current.date(byAdding: .month, value: 3, to: .now)
        }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A progress note, optionally with how far along it is.
private struct GoalNoteSheet: View {
    let onSave: (String, Int?) async throws -> Void
    @State private var note = ""
    @State private var withProgress = false
    @State private var progress = 50.0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("What happened?", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                Toggle("Say how far along", isOn: $withProgress)
                if withProgress {
                    LabeledContent("Progress") {
                        Text("\(Int(progress))%").monospacedDigit()
                    }
                    Slider(value: $progress, in: 0...100, step: 5)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("Add a Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await onSave(note, withProgress ? Int(progress) : nil)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
