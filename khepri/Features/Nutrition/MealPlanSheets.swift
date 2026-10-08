import NorthAPI
import NorthKit
import SwiftUI

/// Add one ingredient to a meal, showing what its day has left and what
/// would remain after the chosen portion.
struct PortionSheet: View {
    let store: MealPlanStore
    let service: NutritionServicing
    let mealID: String

    @State private var query = ""
    @State private var results: [Ingredient] = []
    @State private var picked: Ingredient?
    @State private var grams = 100.0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error = error ?? store.error { ErrorRow(error) }
                if let dayID = store.day(holding: mealID)?.id, let left = store.remaining(on: dayID) {
                    Section("This day has left") { RemainingRow(left: left) }
                }
                if let picked {
                    Section(picked.name) {
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...2000, step: 5)
                        if let dayID = store.day(holding: mealID)?.id,
                           let after = store.remaining(on: dayID, after: picked.per100g, grams: grams) {
                            LabeledContent("After this") { RemainingRow(left: after) }
                        }
                        Button("Add") {
                            Task { if await store.addPortions(to: mealID, [(picked.id, grams)]) { dismiss() } }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(results, id: \.id) { ingredient in
                    Button(ingredient.name) { picked = ingredient }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search ingredients")
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .overagePrompt(store, active: true) { dismiss() }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                do { results = try await service.ingredients(matching: query) } catch { self.error = error.localizedDescription }
            }
        }
    }
}

/// What a day has left of each macro, negative shown as over.
struct RemainingRow: View {
    let left: Macros

    var body: some View {
        HStack(spacing: 12) {
            item("P", left.proteinG)
            item("C", left.carbG)
            item("F", left.fatG)
        }
        .font(.caption.monospacedDigit())
    }

    private func item(_ name: String, _ grams: Double) -> some View {
        Text(grams < -0.5 ? "\(name) \(Int((-grams).rounded())) g over" : "\(name) \(Int(max(grams, 0).rounded())) g left")
            .foregroundStyle(grams < -0.5 ? NorthColor.destructive : .secondary)
    }
}

/// An advanced day's own target: a lower- or higher-carb band or exact carb
/// grams, and protein or fat of its own. Blank follows the plan; the server
/// refuses anything above the daily target.
struct DayTargetSheet: View {
    let store: MealPlanStore
    let dayID: String

    enum Carbs: Hashable {
        case plan
        case band(MealPlanType)
        case grams
    }

    @State private var carbs = Carbs.plan
    @State private var carbG: Double?
    @State private var proteinG: Double?
    @State private var fatG: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.error { ErrorRow(error) }
                Section("Carbs") {
                    Picker("Carbs", selection: $carbs) {
                        Text("Follow the plan").tag(Carbs.plan)
                        ForEach(MealPlanType.presets, id: \.self) { Text("\($0.title) day").tag(Carbs.band($0)) }
                        Text("Exact grams").tag(Carbs.grams)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if carbs == .grams { grams("Carbs", $carbG, limit: target?.carbG) }
                }
                Section {
                    grams("Protein", $proteinG, limit: target?.proteinG)
                    grams("Fat", $fatG, limit: target?.fatG)
                } footer: {
                    Text("Leave blank to follow the plan. Nothing can go above your daily target.")
                }
            }
            .navigationTitle(store.day(dayID)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await store.updateDay(dayID, override) { dismiss() } } }
                }
            }
            .overagePrompt(store, active: true) { dismiss() }
            .onAppear(perform: fill)
        }
    }

    private var target: Macros? { store.plan?.value2.target }

    private var override: MealPlanDayOverride {
        var out = MealPlanDayOverride(proteinG: proteinG, fatG: fatG)
        switch carbs {
        case .plan: break
        case .band(let type): out.carbType = type
        case .grams: out.carbG = carbG
        }
        return out
    }

    private func fill() {
        guard let day = store.day(dayID) else { return }
        if let type = day.carbType { carbs = .band(type) } else if day.carbG != nil { carbs = .grams }
        carbG = day.carbG
        proteinG = day.proteinG
        fatG = day.fatG
    }

    private func grams(_ name: String, _ value: Binding<Double?>, limit: Double?) -> some View {
        LabeledContent("\(name) (g)") {
            TextField(limit.map { "up to \(Int($0))" } ?? "", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A plan's name and carb level. Changing the level moves every day's carbs
/// and leaves protein and fat at the target.
struct PlanSettingsSheet: View {
    let store: MealPlanStore
    @State private var name = ""
    @State private var planType = MealPlanType.midCarb
    @State private var customPct = 40.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error = store.error { ErrorRow(error) }
                TextField("Name", text: $name)
                Section("Carbs") {
                    Picker("Plan type", selection: $planType) {
                        ForEach(store.isAdvanced ? MealPlanType.allCases : MealPlanType.presets, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if planType == .custom {
                        Stepper("\(Int(customPct))% of your carbs", value: $customPct, in: 0...100, step: 5)
                    }
                }
            }
            .navigationTitle("Plan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let pct = planType == .custom ? customPct : nil
                            if await store.updateSettings(name: name, planType: planType, customCarbPct: pct) { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overagePrompt(store, active: true) { dismiss() }
            .onAppear {
                guard let plan = store.plan?.value1 else { return }
                name = plan.name
                planType = plan.planType
                customPct = plan.customCarbPct ?? customPct
            }
        }
    }
}
