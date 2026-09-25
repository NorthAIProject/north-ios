import NorthAPI
import NorthKit
import SwiftUI

/// Check-ins: how you are arriving, one a day. Today's first, then the run of
/// days before it.
struct CheckInsScreen: View {
    var service: CheckInsServicing = CheckInsService()
    var goals: GoalsServicing = GoalsService()

    @State private var list: CheckInList?
    @State private var activeGoals: [GoalSummary] = []
    @State private var error: String?
    @State private var editingToday = false
    @State private var editingPast: PastCheckIn?

    var body: some View {
        Group {
            if let list {
                content(list)
            } else if let error {
                ContentUnavailableView("Check-ins did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Check-ins")
        .sheet(item: $editingPast) { past in
            NavigationStack {
                Form {
                    CheckInForm(title: past.title, existing: past.checkIn, goals: activeGoals) { request in
                        _ = try await service.update(past.checkIn.id, request)
                        editingPast = nil
                        await load()
                    }
                }
                .navigationTitle("Edit Check-in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingPast = nil }
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func content(_ list: CheckInList) -> some View {
        List {
            if let error { ErrorRow(error) }
            if list.streak > 0 {
                Section {
                    Label {
                        Text(list.streak == 1 ? "1 day in a row" : "\(list.streak) days in a row")
                            .font(.system(size: 24, weight: .light))
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: "flame").foregroundStyle(NorthColor.ember)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let today = list.today, !editingToday {
                // The row already says "Today"; a header would say it twice.
                Section {
                    CheckInSummary(checkIn: today)
                    Button("Edit Today's Check-in") { editingToday = true }
                }
            } else {
                CheckInForm(title: "Today", existing: list.today, goals: activeGoals) { request in
                    _ = try await service.saveToday(request)
                    editingToday = false
                    await load()
                }
            }

            let past = list.recent.filter { $0.id != list.today?.id }
            if !past.isEmpty {
                Section("Earlier") {
                    ForEach(past, id: \.id) { checkIn in
                        CheckInSummary(checkIn: checkIn)
                            .swipeActions(edge: .leading) {
                                Button("Edit") { editingPast = PastCheckIn(checkIn: checkIn) }
                                    .tint(NorthColor.signal)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    Task {
                                        do { try await service.delete(checkIn.id); await load() } catch { self.error = error.localizedDescription }
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            list = try await service.checkIns()
            activeGoals = (try? await goals.goals().goals.filter { $0.status == .active }) ?? []
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Today's check-in: two numbers and a few words.
private struct PastCheckIn: Identifiable {
    let checkIn: CheckIn
    var id: String { checkIn.id }

    var title: String {
        guard let date = CalendarDay.date(from: checkIn.localDate) else { return checkIn.localDate }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

/// A day's check-in: two numbers and a few words.
private struct CheckInForm: View {
    let title: String
    let existing: CheckIn?
    let goals: [GoalSummary]
    let onSave: (CheckInRequest) async throws -> Void

    @State private var mood = 3
    @State private var energy = 3
    @State private var wins = ""
    @State private var challenges = ""
    @State private var notes = ""
    @State private var goalID: String?
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Section {
            ScalePicker(title: "Mood", value: $mood)
            ScalePicker(title: "Energy", value: $energy)
        } header: {
            Text(title)
        } footer: {
            Text("1 is rough, 5 is great.")
        }
        Section {
            TextField("A win, however small", text: $wins, axis: .vertical)
            TextField("What got in the way", text: $challenges, axis: .vertical)
            TextField("Anything else", text: $notes, axis: .vertical)
            if !goals.isEmpty {
                Picker("About a goal", selection: $goalID) {
                    Text("None").tag(String?.none)
                    ForEach(goals, id: \.id) { Text($0.title).tag(Optional($0.id)) }
                }
            }
        }
        Section {
            Button(existing == nil ? "Check In" : "Save Changes") { Task { await save() } }
                .disabled(saving)
            if let error { ErrorRow(error) }
        }
        .onAppear(perform: fill)
    }

    private func fill() {
        guard let existing else { return }
        mood = existing.mood
        energy = existing.energy
        wins = existing.wins
        challenges = existing.challenges
        notes = existing.notes
        goalID = existing.relatedGoalId
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await onSave(.init(mood: mood, energy: energy, wins: wins, challenges: challenges, notes: notes, relatedGoalId: goalID))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 1 to 5, as a row of numbers: quicker to hit than a slider, and exact.
private struct ScalePicker: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            Picker(title, selection: $value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInSummary: View {
    let checkIn: CheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day).font(.headline)
                Spacer()
                Text("Mood \(checkIn.mood) · Energy \(checkIn.energy)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !checkIn.wins.isEmpty { Text(checkIn.wins).font(.subheadline) }
            if !checkIn.challenges.isEmpty {
                Text(checkIn.challenges).font(.subheadline).foregroundStyle(.secondary)
            }
            if let goal = checkIn.relatedGoalTitle, !goal.isEmpty {
                Label(goal, systemImage: "target").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var day: String {
        guard let date = CalendarDay.date(from: checkIn.localDate) else { return checkIn.localDate }
        return Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide).day().month())
    }
}
