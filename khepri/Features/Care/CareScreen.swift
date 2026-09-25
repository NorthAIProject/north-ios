import Charts
import NorthAPI
import NorthKit
import SwiftUI

typealias CarePage = Components.Schemas.Care

protocol CareServicing: Sendable {
    func care() async throws -> CarePage
    func logWater(_ ml: Int) async throws -> CarePage
    func undoWater(_ id: String) async throws -> CarePage
    func logSleep(_ request: Components.Schemas.SleepRequest) async throws -> CarePage
    func createHabit(name: String, domain: String, days: [Int]) async throws -> CarePage
    func setHabit(_ id: String, done: Bool) async throws -> CarePage
    func deleteHabit(_ id: String) async throws -> CarePage
    func createReminder(label: String, time: String, days: [Int]) async throws -> CarePage
    func setReminder(_ id: String, enabled: Bool) async throws -> CarePage
    func deleteReminder(_ id: String) async throws -> CarePage
}

struct CareService: CareServicing {
    var api: Client = API.shared

    func care() async throws -> CarePage {
        try await NorthAPI.call { try await api.getCare().ok.body.json }
    }
    func logWater(_ ml: Int) async throws -> CarePage {
        try await NorthAPI.call { try await api.logWater(body: .json(.init(amountMl: ml))).created.body.json }
    }
    func undoWater(_ id: String) async throws -> CarePage {
        try await NorthAPI.call { try await api.undoWater(path: .init(entryID: id)).ok.body.json }
    }
    func logSleep(_ request: Components.Schemas.SleepRequest) async throws -> CarePage {
        try await NorthAPI.call { try await api.logSleep(body: .json(request)).ok.body.json }
    }
    func createHabit(name: String, domain: String, days: [Int]) async throws -> CarePage {
        try await NorthAPI.call { try await api.createHabit(body: .json(.init(name: name, domain: domain, daysOfWeek: days))).created.body.json }
    }
    func setHabit(_ id: String, done: Bool) async throws -> CarePage {
        try await NorthAPI.call { try await api.setHabitDone(path: .init(habitID: id), body: .json(.init(value: done))).ok.body.json }
    }
    func deleteHabit(_ id: String) async throws -> CarePage {
        try await NorthAPI.call { try await api.deleteHabit(path: .init(habitID: id)).ok.body.json }
    }
    func createReminder(label: String, time: String, days: [Int]) async throws -> CarePage {
        try await NorthAPI.call {
            try await api.createCareReminder(body: .json(.init(label: label, timeOfDay: time, daysOfWeek: days))).created.body.json
        }
    }
    func setReminder(_ id: String, enabled: Bool) async throws -> CarePage {
        try await NorthAPI.call {
            try await api.setCareReminderEnabled(path: .init(reminderID: id), body: .json(.init(value: enabled))).ok.body.json
        }
    }
    func deleteReminder(_ id: String) async throws -> CarePage {
        try await NorthAPI.call { try await api.deleteCareReminder(path: .init(reminderID: id)).ok.body.json }
    }
}

/// Water, sleep, habits and reminders: the small things that decide how a
/// day goes. Every change answers with the page, so totals and streaks are
/// always the server's.
struct CareScreen: View {
    var service: CareServicing = CareService()
    @State private var page: CarePage?
    @State private var error: String?
    @State private var loggingSleep = false
    @State private var addingHabit = false
    @State private var addingReminder = false

    var body: some View {
        Group {
            if let page {
                content(page)
            } else if let error {
                ContentUnavailableView("Care did not load", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Care")
        .task { await run { try await service.care() } }
        .refreshable { await run { try await service.care() } }
        .sheet(isPresented: $loggingSleep) {
            SleepSheet { request in
                await run { try await service.logSleep(request) }
            }
        }
        .sheet(isPresented: $addingHabit) {
            HabitSheet { name, domain, days in
                await run { try await service.createHabit(name: name, domain: domain, days: days) }
            }
        }
        .sheet(isPresented: $addingReminder) {
            ReminderSheet { label, time, days in
                await run { try await service.createReminder(label: label, time: time, days: days) }
            }
        }
    }

    private func content(_ page: CarePage) -> some View {
        List {
            if let error { ErrorRow(error) }
            waterSection(page.water)
            sleepSection(page.lastNight)
            habitsSection(page.habits)
            remindersSection(page.reminders)
            if page.waterWeek.contains(where: { $0.value > 0 }) || page.sleepWeek.contains(where: { $0.value > 0 }) {
                Section("This Week") {
                    WeekBars(title: "Water (ml)", points: page.waterWeek)
                    WeekBars(title: "Sleep (h)", points: page.sleepWeek)
                }
            }
        }
    }

    private func waterSection(_ water: Components.Schemas.Care.WaterPayload) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(water.totalMl)")
                        .font(.system(size: 36, weight: .light).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("of \(water.targetMl) ml").foregroundStyle(.secondary)
                }
                Gauge(value: Double(min(water.totalMl, water.targetMl)), in: 0...Double(max(water.targetMl, 1))) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(NorthColor.signal)
                    .accessibilityLabel("\(water.totalMl) of \(water.targetMl) millilitres")
                HStack(spacing: 12) {
                    ForEach([250, 500], id: \.self) { ml in
                        Button("+\(ml) ml") { Task { await run { try await service.logWater(ml) } } }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
            ForEach(water.entries, id: \.id) { entry in
                LabeledContent("\(entry.amountMl) ml", value: entry.loggedAt.formatted(date: .omitted, time: .shortened))
                    .swipeActions {
                        Button("Undo", role: .destructive) { Task { await run { try await service.undoWater(entry.id) } } }
                    }
            }
        } header: {
            Text("Water")
        }
    }

    private func sleepSection(_ night: Components.Schemas.Care.LastNightPayload?) -> some View {
        Section("Last Night") {
            if let night {
                LabeledContent("Slept", value: Duration.seconds(night.durationMinutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                if let quality = night.quality { LabeledContent("Quality", value: "\(quality) of 5") }
                if let bed = night.bedtime, let wake = night.wakeTime, !bed.isEmpty { LabeledContent("In bed", value: "\(bed) – \(wake)") }
            }
            Button(night == nil ? "Log Last Night" : "Change") { loggingSleep = true }
        }
    }

    private func habitsSection(_ habits: [Components.Schemas.Care.HabitsPayloadPayload]) -> some View {
        Section {
            ForEach(habits, id: \.id) { habit in
                Button {
                    Task { await run { try await service.setHabit(habit.id, done: !habit.doneToday) } }
                } label: {
                    HStack {
                        Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(NorthColor.signal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(habit.name).foregroundStyle(.primary)
                            Text(habit.streak > 0 ? "\(habit.streak)-day streak" : habit.scheduledToday ? "Due today" : "Not today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    // A plain button is hittable only where it draws; the
                    // label spans the row so the whole row is the target.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                // Plain, so the name reads as text rather than a link.
                .buttonStyle(.plain)
                .accessibilityValue(habit.doneToday ? "Done" : "Not done")
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await run { try await service.deleteHabit(habit.id) } } }
                }
            }
            Button("Add a Habit", systemImage: "plus") { addingHabit = true }
        } header: {
            Text("Habits")
        }
    }

    private func remindersSection(_ reminders: [Components.Schemas.Care.RemindersPayloadPayload]) -> some View {
        Section {
            ForEach(reminders, id: \.id) { reminder in
                Toggle(isOn: Binding(
                    get: { reminder.enabled },
                    set: { on in Task { await run { try await service.setReminder(reminder.id, enabled: on) } } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.label)
                        Text(reminder.due ? "\(reminder.timeOfDay) · due now" : reminder.timeOfDay)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(reminder.due ? NorthColor.ember : .secondary)
                    }
                }
                .tint(NorthColor.signal)
                .swipeActions {
                    Button("Delete", role: .destructive) { Task { await run { try await service.deleteReminder(reminder.id) } } }
                }
            }
            Button("Add a Reminder", systemImage: "plus") { addingReminder = true }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Nudges for things like protein after training. Your coach sends them where you read them.")
        }
    }

    private func run(_ load: () async throws -> CarePage) async {
        do { page = try await load(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct WeekBars: View {
    let title: String
    let points: [Components.Schemas.CarePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                BarMark(x: .value("Day", point.label), y: .value(title, point.value))
                    .foregroundStyle(NorthColor.signal)
            }
            .frame(height: 100)
        }
        .padding(.vertical, 4)
    }
}

/// The seven weekday toggles shared by habits and reminders. 0 is Sunday.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { day in
                let symbol = Calendar.current.veryShortWeekdaySymbols[day]
                Button(symbol) {
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                }
                .buttonStyle(.bordered)
                .tint(days.contains(day) ? NorthColor.signal : .secondary)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day])
                .accessibilityAddTraits(days.contains(day) ? .isSelected : [])
            }
        }
    }
}

private struct SleepSheet: View {
    let onSave: (Components.Schemas.SleepRequest) async -> Void
    @State private var hours = 7
    @State private var minutes = 30
    @State private var quality = 3
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Stepper("\(hours) h", value: $hours, in: 0...16)
                Stepper("\(minutes) min", value: $minutes, in: 0...55, step: 5)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quality")
                    Picker("Quality", selection: $quality) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .navigationTitle("Last Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSave(.init(durationMinutes: hours * 60 + minutes, quality: quality))
                            dismiss()
                        }
                    }
                    .disabled(hours * 60 + minutes == 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct HabitSheet: View {
    let onSave: (String, String, [Int]) async -> Void
    @State private var name = ""
    @State private var domain = "health"
    @State private var days: Set<Int> = Set(0..<7)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("e.g. Stretch 10 minutes", text: $name)
                Picker("Area", selection: $domain) {
                    ForEach(["fitness", "health", "work", "learning", "personal", "other"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                Section("On") { WeekdayPicker(days: $days) }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await onSave(name, domain, days.sorted()); dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || days.isEmpty)
                }
            }
        }
    }
}

private struct ReminderSheet: View {
    let onSave: (String, String, [Int]) async -> Void
    @State private var label = ""
    @State private var time = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: .now) ?? .now
    @State private var days: Set<Int> = Set(0..<7)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("e.g. Protein after training", text: $label)
                DatePicker("At", selection: $time, displayedComponents: .hourAndMinute)
                Section("On") { WeekdayPicker(days: $days) }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await onSave(label, ClockTime.string(from: time), days.sorted()); dismiss() }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
