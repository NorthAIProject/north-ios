import NorthAPI
import SwiftUI

/// The weekly review: the week that happened, then up to three priorities,
/// goals in order, and how hard to train. Four short steps, opened from the
/// Sunday nudge or More.
struct WeeklyReviewFlow: View {
    var service: WeeklyServicing = WeeklyService()
    @Environment(\.dismiss) private var dismiss
    @State private var review: WeeklyReview?
    @State private var draft = WeeklyDraft()
    @State private var step = Step.week
    @State private var error: String?
    @State private var saving = false
    @State private var saved = false

    enum Step: Int, CaseIterable {
        case week, priorities, goals, training

        var title: String {
            switch self {
            case .week: "The Week"
            case .priorities: "Priorities"
            case .goals: "Goals in Order"
            case .training: "Training"
            }
        }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .safeAreaInset(edge: .bottom) { footer }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let review {
            switch step {
            case .week: WeekStep(review: review)
            case .priorities: PrioritiesStep(draft: $draft)
            case .goals: GoalsOrderStep(review: review, draft: $draft)
            case .training: TrainingStep(draft: $draft, saved: saved)
            }
        } else if let error {
            ContentUnavailableView("Could Not Load", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let error, review != nil {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                if step != .week {
                    Button("Back") { move(-1) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if saved {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else if step == .training {
                    Button("Save the Week") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(saving)
                } else {
                    Button("Next") { move(1) }
                        .buttonStyle(.borderedProminent)
                        .disabled(review == nil)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func move(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func load() async {
        do {
            let loaded = try await service.review()
            review = loaded
            draft = WeeklyDraft(review: loaded)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await service.setFocus(priorities: draft.submittedPriorities, goalOrder: draft.goalOrder, volume: draft.volume)
            error = nil
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct WeekStep: View {
    let review: WeeklyReview

    var body: some View {
        List {
            if let last = review.last, !last.priorities.isEmpty {
                Section("You Chose") {
                    ForEach(last.priorities, id: \.self) { Text($0) }
                }
            }
            Section {
                if let report = review.report, report.ready {
                    MarkdownBlocksView(markdown: report.body)
                } else {
                    Text("Your weekly report is being written. You can plan the week now and read it later in Reports.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct PrioritiesStep: View {
    @Binding var draft: WeeklyDraft

    var body: some View {
        Form {
            Section {
                ForEach(0..<WeeklyDraft.maxPriorities, id: \.self) { index in
                    TextField("Priority \(index + 1)", text: $draft.priorities[index])
                }
            } footer: {
                Text("Up to three things this week is for. Your coach plans around them.")
            }
        }
    }
}

private struct GoalsOrderStep: View {
    let review: WeeklyReview
    @Binding var draft: WeeklyDraft

    private func title(_ id: String) -> String {
        review.goals.first { $0.id == id }?.title ?? ""
    }

    var body: some View {
        if draft.goalOrder.isEmpty {
            ContentUnavailableView("No Active Goals", systemImage: "target", description: Text("Nothing to put in order this week."))
        } else {
            List {
                Section {
                    ForEach(draft.goalOrder, id: \.self) { id in
                        Text(title(id))
                    }
                    .onMove { draft.goalOrder.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Drag to put the most important first. Your goals list and coach follow this order.")
                }
            }
            .environment(\.editMode, .constant(.active))
        }
    }
}

private struct TrainingStep: View {
    @Binding var draft: WeeklyDraft
    let saved: Bool

    var body: some View {
        Form {
            Section {
                Picker("Volume", selection: $draft.volume) {
                    ForEach([WeeklyVolume.hold, .build, .deload], id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(draft.volume.explanation).foregroundStyle(.secondary)
            } footer: {
                Text("Only for the week being planned. The week after goes back to your plan unless you choose again.")
            }
            if saved {
                Section {
                    Label("Saved. Your goals, coach and training plan use this focus now.", systemImage: "checkmark.circle")
                }
            }
        }
    }
}
