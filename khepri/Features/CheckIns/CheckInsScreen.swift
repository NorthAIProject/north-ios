import NorthAPI
import NorthKit
import SwiftUI

/// Check-ins: how you are arriving, one a day. Today's first, then the run of
/// days before it.
struct CheckInsScreen: View {
    var service: CheckInsServicing = CheckInsService()
    var goals: GoalsServicing = GoalsService()

    @Environment(AppRouter.self) private var router
    @State private var list: CheckInList?
    @State private var activeGoals: [GoalSummary] = []
    @State private var error: String?
    @State private var editingToday = false
    @State private var editingPast: PastCheckIn?
    /// The mood a nudge's button picked, until today's form takes it.
    @State private var startingMood: Int?
    /// The router's data version the last load started at, so this screen's
    /// own writes, which load right away, do not load a second time.
    @State private var loadedVersion: Int?

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
                        await didWrite()
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
        // Reloads on any write elsewhere in the app: the coach, Siri, Today.
        .task(id: router.dataVersion) {
            guard loadedVersion != router.dataVersion else { return }
            await load()
        }
        .refreshable { await load() }
        .onChange(of: router.checkInMood, initial: true) { _, mood in
            guard let mood else { return }
            router.checkInMood = nil
            startingMood = mood
        }
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
                CheckInForm(title: "Today", existing: list.today, goals: activeGoals, startingMood: startingMood) { request in
                    _ = try await service.saveToday(request)
                    editingToday = false
                    await didWrite()
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
                                        do {
                                            try await service.delete(checkIn.id)
                                            await didWrite()
                                        } catch {
                                            self.error = error.localizedDescription
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
    }

    /// Tells every screen showing the day, then reloads this one.
    private func didWrite() async {
        router.dataChanged()
        await load()
    }

    private func load() async {
        loadedVersion = router.dataVersion
        do {
            list = try await service.checkIns()
            activeGoals = (try? await goals.goals().goals.filter { $0.status == .active }) ?? []
            error = nil
        } catch {
            // A newer change cancelled this load and started the next one.
            if Task.isCancelled { return }
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

/// A day's check-in: two numbers and a few words, and optionally how stressed
/// and how well slept, and a few tags.
private struct CheckInForm: View {
    let title: String
    let existing: CheckIn?
    let goals: [GoalSummary]
    /// Where the mood starts when there is no check-in yet to edit.
    var startingMood: Int? = nil
    let onSave: (CheckInRequest) async throws -> Void

    @State private var mood = 3
    @State private var energy = 3
    @State private var stress: Int?
    @State private var sleepQuality: Int?
    @State private var wins = ""
    @State private var challenges = ""
    @State private var notes = ""
    @State private var tags = ""
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
            OptionalScalePicker(title: "Stress", value: $stress)
            OptionalScalePicker(title: "Sleep quality", value: $sleepQuality)
        } footer: {
            Text("Optional. Stress: 1 is calm, 5 is overwhelmed. Sleep: 1 is poor, 5 is great.")
        }
        Section {
            TextField("A win, however small", text: $wins, axis: .vertical)
            TextField("What got in the way", text: $challenges, axis: .vertical)
            TextField("Anything else", text: $notes, axis: .vertical)
            TextField("Tags, separated by commas", text: $tags)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
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
        .onChange(of: startingMood) { fill() }
    }

    private func fill() {
        guard let existing else {
            if let startingMood { mood = startingMood }
            return
        }
        mood = existing.mood
        energy = existing.energy
        stress = existing.stress
        sleepQuality = existing.sleepQuality
        wins = existing.wins
        challenges = existing.challenges
        notes = existing.notes
        tags = CheckInTags.text(existing.tags)
        goalID = existing.relatedGoalId
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let request = CheckInRequest(
            mood: mood, energy: energy, wins: wins, challenges: challenges, notes: notes, relatedGoalId: goalID,
            stress: stress, sleepQuality: sleepQuality, tags: CheckInTags.parse(tags), source: CheckInSource.app
        )
        do {
            try await onSave(request)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 1 to 5, as a row of numbers: quicker to hit than a slider, and exact.
private struct ScalePicker: View {
    let title: LocalizedStringKey
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

/// A 1-to-5 scale that may stay unanswered: nothing is picked until a number
/// is tapped, and Clear takes the answer back.
private struct OptionalScalePicker: View {
    let title: LocalizedStringKey
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if value != nil {
                    Button("Clear") { value = nil }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
            Picker(title, selection: $value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag(Optional($0)) }
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
            if let extras {
                Text(extras)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !checkIn.wins.isEmpty { Text(checkIn.wins).font(.subheadline) }
            if !checkIn.challenges.isEmpty {
                Text(checkIn.challenges).font(.subheadline).foregroundStyle(.secondary)
            }
            if !checkIn.notes.isEmpty {
                Text(checkIn.notes).font(.subheadline).foregroundStyle(.secondary)
            }
            if let goal = checkIn.relatedGoalTitle, !goal.isEmpty {
                Label(goal, systemImage: "target").font(.caption).foregroundStyle(.secondary)
            }
            if !checkIn.tags.isEmpty {
                CheckInTagChips(tags: checkIn.tags)
                    .padding(.top, 2)
            }
            Label(provenance, systemImage: CheckInSource.systemImage(checkIn.source))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var day: String {
        guard let date = CalendarDay.date(from: checkIn.localDate) else { return checkIn.localDate }
        return Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide).day().month())
    }

    /// Stress and sleep, when the check-in has them.
    private var extras: String? {
        let parts = [
            checkIn.stress.map { String(localized: "Stress \($0)") },
            checkIn.sleepQuality.map { String(localized: "Sleep \($0)") }
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// When and where it was filed, and when it last changed: "08:15 ·
    /// iPhone · edited 21:40".
    private var provenance: String {
        var parts = [
            checkIn.createdAt.formatted(date: .omitted, time: .shortened),
            CheckInSource.label(checkIn.source)
        ]
        if checkIn.wasEdited {
            parts.append(String(localized: "edited \(checkIn.updatedAt.formatted(date: .omitted, time: .shortened))"))
        }
        return parts.joined(separator: " · ")
    }
}
