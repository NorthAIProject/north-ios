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
    @State private var limitations = ""
    @State private var creating = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    /// The vocabulary the server's plan validator enforces.
    static let equipmentOptions: [(value: String, label: String)] = [
        ("dumbbell", "Dumbbells"), ("barbell", "Barbell"), ("kettlebell", "Kettlebells"),
        ("pull-up bar", "Pull-up bar"), ("bench", "Bench"), ("resistance band", "Resistance bands"),
        ("machine", "Machines / cables"), ("treadmill", "Treadmill"), ("bike", "Bike"), ("rower", "Rower"),
    ]

    static let experienceOptions: [(value: String, label: String)] = [
        ("beginner", "New to training"), ("returning", "Coming back after a break"),
        ("intermediate", "Training regularly"), ("advanced", "Years of consistent training"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What are you training for?", text: $goal, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("A race, getting stronger, feeling better. Your own words.")
                }

                Section {
                    Picker("Experience", selection: $experience) {
                        ForEach(Self.experienceOptions, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Stepper("\(daysPerWeek) days a week", value: $daysPerWeek, in: 1...7)
                    Stepper("\(sessionMinutes) minutes a session", value: $sessionMinutes, in: 10...240, step: 5)
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
                    TextField("Injuries, limits, preferences", text: $limitations, axis: .vertical)
                        .lineLimit(2...4)
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

    private func prefill() async {
        guard let last = try? await service.latestIntake() else { return }
        goal = last.goal
        experience = last.experience
        daysPerWeek = last.daysPerWeek
        sessionMinutes = last.sessionMinutes
        equipment = Set(last.equipment)
        limitations = last.limitations ?? ""
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let plan = try await service.createPlan(TrainingIntake(
                goal: goal, experience: experience, daysPerWeek: daysPerWeek, sessionMinutes: sessionMinutes,
                equipment: Array(equipment), limitations: limitations.isEmpty ? nil : limitations
            ))
            onCreated(plan)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
