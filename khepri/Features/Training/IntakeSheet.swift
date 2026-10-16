import NorthAPI
import SwiftUI

/// The questions a plan is built from, the same as the web's intake.
struct IntakeSheet: View {
    let service: TrainingServicing
    let onCreated: (PlanDetail) -> Void

    @State private var goal = ""
    @State private var experience = "beginner"
    @State private var daysPerWeek = 3
    @State private var sessionMinutes = 45
    @State private var equipment: Set<String> = []
    @State private var weekdays: Set<String> = []
    @State private var limitations = ""
    @State private var creating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    /// The vocabulary the server's plan validator enforces.
    static let equipmentOptions: [(value: String, label: String)] = [
        ("dumbbell", String(localized: "Dumbbells")),
        ("barbell", String(localized: "Barbell")),
        ("kettlebell", String(localized: "Kettlebells")),
        ("pull-up bar", String(localized: "Pull-up bar")),
        ("bench", String(localized: "Bench", comment: "Training equipment")),
        ("resistance band", String(localized: "Resistance bands")),
        ("machine", String(localized: "Machines / cables")),
        ("treadmill", String(localized: "Treadmill")),
        ("bike", String(localized: "Bike", comment: "Training equipment")),
        ("rower", String(localized: "Rower", comment: "Training equipment")),
    ]

    static let experienceOptions: [(value: String, label: String)] = [
        ("beginner", String(localized: "New to training")),
        ("returning", String(localized: "Coming back after a break")),
        ("intermediate", String(localized: "Training regularly")),
        ("advanced", String(localized: "Years of consistent training")),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top) {
                        TextField("What are you training for?", text: $goal, axis: .vertical)
                            .lineLimit(2...4)
                        DictationButton(text: $goal, font: .body)
                    }
                } footer: {
                    Text("A race, getting stronger, feeling better. Your own words.")
                }

                Section {
                    Picker("Experience", selection: $experience) {
                        ForEach(Self.experienceOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Stepper("\(trainingDays) days a week", value: $daysPerWeek, in: 1...7)
                        .disabled(!weekdays.isEmpty)
                    Stepper("\(sessionMinutes) minutes a session", value: $sessionMinutes, in: 10...240, step: 5)
                }

                Section {
                    WeekdayChips(selected: weekdays, completed: []) { weekday in
                        if weekdays.contains(weekday) { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    }
                } header: {
                    Text("Which Days?")
                } footer: {
                    Text("""
                        Optional. The days you pick set how many a week; \
                        pick none and the plan spreads them across your week.
                        """)
                }

                Section {
                    ForEach(Self.equipmentOptions, id: \.value) { option in
                        Toggle(option.label, isOn: Binding(
                            get: { equipment.contains(option.value) },
                            set: { if $0 { equipment.insert(option.value) } else { equipment.remove(option.value) } }
                        ))
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text("Leave everything off for bodyweight only. Nothing outside this list will appear in your plan.")
                }

                Section("Anything to work around?") {
                    HStack(alignment: .top) {
                        TextField("Injuries, limits, preferences", text: $limitations, axis: .vertical)
                            .lineLimit(2...4)
                        DictationButton(text: $limitations, font: .body)
                    }
                }

                if let error { ErrorRow(error) }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(creating) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(goal.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                }
            }
            .overlay {
                if creating {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Building your plan…").font(.headline)
                        Text("This can take up to a minute.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 10))
                }
            }
            .interactiveDismissDisabled(creating)
            .task { await prefill() }
        }
    }

    /// The days a week the plan is built for: the days picked, when any are.
    private var trainingDays: Int { weekdays.isEmpty ? daysPerWeek : weekdays.count }

    private func prefill() async {
        guard let last = try? await service.latestIntake() else { return }
        goal = last.goal
        experience = last.experience
        daysPerWeek = last.daysPerWeek
        sessionMinutes = last.sessionMinutes
        equipment = Set(last.equipment)
        weekdays = Set(last.weekdays ?? [])
        limitations = last.limitations ?? ""
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let plan = try await service.createPlan(TrainingIntake(
                goal: goal, experience: experience, daysPerWeek: trainingDays, sessionMinutes: sessionMinutes,
                equipment: Array(equipment), limitations: limitations.isEmpty ? nil : limitations,
                weekdays: weekdays.isEmpty ? nil : WeekEditorSheet.allWeekdays.filter(weekdays.contains)
            ))
            onCreated(plan)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
