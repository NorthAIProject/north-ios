import NorthAPI
import SwiftUI

/// What the coach builds a meal plan around: the objective, how many days and
/// meals, the carb level, and the foods to leave out.
///
/// Opens with the answers last given, so asking again is one tap.
struct MealGenerateForm: View {
    let service: PlanImportServicing
    let disabled: Bool
    /// Why the last build failed, shown under the form.
    let buildError: String?
    let onBuild: (MealPlanIntake) -> Void

    @State private var loaded = false
    @State private var hasTarget = true
    @State private var objective = "maintenance"
    @State private var days = 3
    @State private var mealsPerDay = 4
    @State private var planType = MealPlanType.midCarb
    @State private var exclusions = ""
    @State private var notes = ""
    @State private var loadError: String?

    var body: some View {
        Form {
            if !loaded {
                ProgressView()
            } else if !hasTarget {
                Section {
                    Text("""
                        Meal plans are built to your macro target, and you haven't worked one out yet. \
                        Use the calculator in Nutrition first.
                        """)
                }
            } else {
                answers
            }
            if let message = buildError ?? loadError { ErrorRow(message) }
        }
        .task { await load() }
    }

    @ViewBuilder private var answers: some View {
        Section {
            Picker("Goal", selection: $objective) {
                Text("Lose fat").tag("cutting")
                Text("Maintain").tag("maintenance")
                Text("Build muscle").tag("bulking")
            }
            Stepper(value: $days, in: 1...7) {
                LabeledContent("Different days", value: days, format: .number)
            }
            Stepper(value: $mealsPerDay, in: 1...8) {
                LabeledContent("Meals per day", value: mealsPerDay, format: .number)
            }
            Picker("Carbs", selection: $planType) {
                ForEach(MealPlanType.presets, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
        } footer: {
            Text("Every day is built to your macro target and checked against your answers before you see it.")
        }
        Section {
            TextField("dairy, peanuts, mushrooms", text: $exclusions, axis: .vertical)
                .lineLimit(1...3)
                .accessibilityIdentifier("meal-generate.exclusions")
        } header: {
            Text("Foods to Leave Out")
        } footer: {
            Text("Separate them with commas. Khepri also keeps them in mind when you chat.")
        }
        Section("Anything Else?") {
            TextField("Cheap, quick breakfasts. Optional.", text: $notes, axis: .vertical)
                .lineLimit(1...4)
        }
        Section {
            Button("Build My Plan", systemImage: "sparkles") { onBuild(intake) }
                .disabled(disabled)
                .accessibilityIdentifier("meal-generate.build")
        } footer: {
            Text("This takes up to a minute. You'll review every meal before anything is saved.")
        }
    }

    private var intake: MealPlanIntake {
        MealPlanIntake(
            objective: objective,
            days: days,
            mealsPerDay: mealsPerDay,
            planType: planType.rawValue,
            exclusions: exclusions
                .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func load() async {
        guard !loaded else { return }
        defer { loaded = true }
        do {
            let state = try await service.mealIntake()
            hasTarget = state.hasTarget
            guard let last = state.intake?.value1 else { return }
            objective = last.objective
            days = last.days
            mealsPerDay = last.mealsPerDay
            planType = MealPlanType(rawValue: last.planType) ?? .midCarb
            exclusions = last.exclusions.joined(separator: ", ")
            notes = last.notes
        } catch {
            // The form still works without last time's answers.
            loadError = error.importMessage
        }
    }
}
