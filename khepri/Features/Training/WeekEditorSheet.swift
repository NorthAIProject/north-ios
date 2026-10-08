import NorthAPI
import NorthKit
import SwiftUI

/// Changes which days a week trains, and what each one is.
///
/// Every change asks the server what week it would make, so the sessions are
/// shown landing on their days before anything is saved: each chosen day takes
/// the next session of the plan, and what is left over carries into the week
/// after. Days already trained this week stay as they were.
struct WeekEditorSheet: View {
    let store: TrainingStore

    @State private var nextWeek = false
    @State private var weekdays: Set<String> = []
    @State private var sourcePlanID: String?
    /// Days pinned to a specific session, by weekday.
    @State private var pinned: [String: SessionChoice] = [:]
    @State private var preview: TrainingWeek?
    @State private var matching: [PlanSummary] = []
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    static let allWeekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Week", selection: $nextWeek) {
                        Text("This Week").tag(false)
                        Text("Next Week").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Stepper(value: dayCount, in: 0...7) {
                        LabeledContent("Days", value: weekdays.isEmpty ? "Rest week" : "\(weekdays.count)")
                    }
                    WeekdayChips(selected: weekdays, completed: completedWeekdays) { weekday in
                        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                        pinned[weekday] = nil
                        Task { await suggest() }
                    }
                } header: {
                    Text("Days")
                } footer: {
                    Text("Changing the number of days suggests which ones. Tap a day to add or drop it.")
                }

                if store.allPlans.count > 1 {
                    Section("Sessions From") {
                        Picker("Plan", selection: sourceBinding) {
                            ForEach(store.allPlans, id: \.id) { plan in
                                Text(plan.name).tag(Optional(plan.id))
                            }
                        }
                        ForEach(matching, id: \.id) { plan in
                            Button("Use \(plan.name) — built for \(plan.days.count) days") {
                                sourcePlanID = plan.id
                                pinned = [:]
                                Task { await suggest(days: plan.days.count) }
                            }
                        }
                    }
                }

                if let preview, !preview.days.isEmpty {
                    Section("Sessions") {
                        ForEach(preview.days, id: \.date) { session in
                            sessionRow(session)
                        }
                    }
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline) }
                }

                if store.week?.custom == true || preview?.custom == true {
                    Section {
                        Button("Back to Your Usual Week", role: .destructive) { Task { await reset() } }
                    }
                }
            }
            .navigationTitle(nextWeek ? "Next Week" : "This Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving)
                }
            }
            .task(id: nextWeek) { await start() }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: WeekSession) -> some View {
        if session.completed {
            LabeledContent(session.weekday) {
                Label(session.focus, systemImage: "checkmark.circle.fill")
            }
        } else {
            Picker(session.weekday, selection: sessionBinding(session.weekday)) {
                Text(rotationLabel(session)).tag(SessionChoice?.none)
                ForEach(store.allPlans, id: \.id) { plan in
                    ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                        Text("\(plan.name) · \(day.focus)").tag(Optional(SessionChoice(planID: plan.id, dayIndex: index)))
                    }
                }
            }
        }
    }

    // MARK: State

    private var completedWeekdays: Set<String> {
        Set((preview?.days ?? []).filter(\.completed).map(\.weekday))
    }

    private var dayCount: Binding<Int> {
        Binding(get: { weekdays.count }, set: { count in
            pinned = [:]
            Task { await suggest(days: count) }
        })
    }

    private var sourceBinding: Binding<String?> {
        Binding(get: { sourcePlanID }, set: { id in
            sourcePlanID = id
            pinned = [:]
            Task { await suggest() }
        })
    }

    private func sessionBinding(_ weekday: String) -> Binding<SessionChoice?> {
        Binding(get: { pinned[weekday] }, set: { choice in
            pinned[weekday] = choice
            Task { await suggest() }
        })
    }

    /// The choice that leaves a day to the rotation. The preview names the
    /// session the rotation gives it, unless the day is pinned to another.
    private func rotationLabel(_ session: WeekSession) -> String {
        pinned[session.weekday] == nil ? "Next in your plan · \(session.focus)" : "Next in your plan"
    }

    // MARK: Server

    private func start() async {
        error = nil
        pinned = [:]
        sourcePlanID = store.plan?.id
        do {
            let current: TrainingWeek
            if !nextWeek, let shown = store.week {
                current = shown
            } else {
                current = try await store.service.week(next: nextWeek)
            }
            weekdays = Set(current.days.map(\.weekday))
            preview = current
            for session in current.days where session.planId != store.plan?.id && !session.completed {
                pinned[session.weekday] = SessionChoice(planID: session.planId, dayIndex: session.dayIndex)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Asks the server for the week the current choices make. With days, it
    /// suggests the weekdays too.
    private func suggest(days: Int? = nil) async {
        do {
            let suggestion = try await store.service.suggestWeek(request(days: days), next: nextWeek)
            error = nil
            preview = suggestion.week
            weekdays = Set(suggestion.week.days.map(\.weekday))
            matching = suggestion.matchingPlans.filter { $0.id != sourcePlanID }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await store.saveWeek(request(), next: nextWeek)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reset() async {
        do {
            try await store.resetWeek(next: nextWeek)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func request(days: Int? = nil) -> WeekRequest {
        if let days {
            return WeekRequest(weekdays: [], days: days, planId: sourcePlanID)
        }
        let ordered = Self.allWeekdays.filter(weekdays.contains)
        let assignments = ordered.compactMap { weekday in
            pinned[weekday].map { Components.Schemas.WeekAssignment(weekday: weekday, planId: $0.planID, dayIndex: $0.dayIndex) }
        }
        return WeekRequest(weekdays: ordered, planId: sourcePlanID, assignments: assignments.isEmpty ? nil : assignments)
    }
}

/// One session of one saved plan.
struct SessionChoice: Hashable {
    let planID: String
    let dayIndex: Int
}

/// The seven days as toggles. A day already trained cannot be dropped.
private struct WeekdayChips: View {
    let selected: Set<String>
    let completed: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WeekEditorSheet.allWeekdays, id: \.self) { weekday in
                let on = selected.contains(weekday)
                Button(String(weekday.prefix(1))) { toggle(weekday) }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(on ? NorthColor.signal : Color.secondary.opacity(0.15), in: .circle)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .buttonStyle(.plain)
                    .disabled(completed.contains(weekday))
                    .accessibilityLabel(weekday)
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
