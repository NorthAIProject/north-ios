import NorthAPI
import NorthKit
import SwiftUI

typealias FoodLog = Components.Schemas.FoodLog
typealias Ingredient = Components.Schemas.Ingredient
typealias MealPlanSummary = Components.Schemas.MealPlanSummary
typealias MealPlanDetail = Components.Schemas.MealPlanDetail
typealias Macros = Components.Schemas.Macros

protocol NutritionServicing: Sendable {
    func log() async throws -> FoodLog
    func logFood(_ ingredientID: String, grams: Double) async throws -> FoodLog
    func logMeal(_ mealID: String) async throws -> FoodLog
    func deleteEntry(_ id: String) async throws -> FoodLog
    func ingredients(matching query: String) async throws -> [Ingredient]
    func createIngredient(name: String, per100g: Macros) async throws
    func deleteIngredient(_ id: String) async throws
    func plans() async throws -> [MealPlanSummary]
    func plan(_ id: String) async throws -> MealPlanDetail
    func createPlan(name: String) async throws -> MealPlanDetail
    func deletePlan(_ id: String) async throws
    func addMeal(to planID: String, name: String, number: Int) async throws -> MealPlanDetail
    func removeMeal(_ id: String) async throws
    func addPortion(to mealID: String, ingredientID: String, grams: Double) async throws
    func removePortion(_ id: String) async throws
}

struct NutritionService: NutritionServicing {
    var api: Client = API.shared

    func log() async throws -> FoodLog { try await NorthAPI.call { try await api.getFoodLog().ok.body.json } }
    func logFood(_ ingredientID: String, grams: Double) async throws -> FoodLog {
        try await NorthAPI.call { try await api.logFood(body: .json(.init(ingredientId: ingredientID, quantityGrams: grams))).created.body.json }
    }
    func logMeal(_ mealID: String) async throws -> FoodLog {
        try await NorthAPI.call { try await api.logPlanMeal(body: .json(.init(mealId: mealID))).created.body.json }
    }
    func deleteEntry(_ id: String) async throws -> FoodLog {
        try await NorthAPI.call { try await api.deleteFoodLogEntry(path: .init(entryID: id)).ok.body.json }
    }
    func ingredients(matching query: String) async throws -> [Ingredient] {
        try await NorthAPI.call { try await api.searchIngredients(query: .init(q: query.isEmpty ? nil : query)).ok.body.json.ingredients }
    }
    func createIngredient(name: String, per100g: Macros) async throws {
        try await NorthAPI.call { _ = try await api.createIngredient(body: .json(.init(name: name, per100g: per100g))).created }
    }
    func deleteIngredient(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteIngredient(path: .init(ingredientID: id)).noContent }
    }
    func plans() async throws -> [MealPlanSummary] { try await NorthAPI.call { try await api.listMealPlans().ok.body.json.plans } }
    func plan(_ id: String) async throws -> MealPlanDetail {
        try await NorthAPI.call { try await api.getMealPlan(path: .init(planID: id)).ok.body.json }
    }
    func createPlan(name: String) async throws -> MealPlanDetail {
        try await NorthAPI.call { try await api.createMealPlan(body: .json(.init(name: name))).created.body.json }
    }
    func deletePlan(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteMealPlan(path: .init(planID: id)).noContent }
    }
    func addMeal(to planID: String, name: String, number: Int) async throws -> MealPlanDetail {
        try await NorthAPI.call {
            try await api.addPlanMeal(path: .init(planID: planID), body: .json(.init(name: name, mealNumber: number))).created.body.json
        }
    }
    func removeMeal(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.removePlanMeal(path: .init(mealID: id)).noContent }
    }
    func addPortion(to mealID: String, ingredientID: String, grams: Double) async throws {
        try await NorthAPI.call {
            _ = try await api.addMealPortion(path: .init(mealID: mealID), body: .json(.init(ingredientId: ingredientID, quantityGrams: grams))).created
        }
    }
    func removePortion(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.removeMealPortion(path: .init(mealIngredientID: id)).noContent }
    }
}

/// What you ate today against your goal, your meal plans, and the
/// ingredients both are built from.
struct NutritionScreen: View {
    var service: NutritionServicing = NutritionService()

    enum Part: String, CaseIterable, Identifiable {
        case today = "Today", plans = "Plans", ingredients = "Ingredients"
        var id: String { rawValue }
    }

    @State private var part = Part.today

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $part) {
                ForEach(Part.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch part {
            case .today: FoodLogView(service: service)
            case .plans: MealPlansView(service: service)
            case .ingredients: IngredientsView(service: service)
            }
        }
        .navigationTitle("Nutrition")
    }
}

// MARK: - Today

private struct FoodLogView: View {
    let service: NutritionServicing
    @State private var log: FoodLog?
    @State private var error: String?
    @State private var adding = false

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let log {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(log.totals.calories.formatted(.number.precision(.fractionLength(0))))
                                .font(.system(size: 36, weight: .light).monospacedDigit())
                            Text(log.progress.map { "of \(Int($0.goal.calories)) kcal" } ?? "kcal").foregroundStyle(.secondary)
                        }
                        if let goal = log.progress?.goal {
                            Gauge(value: min(log.totals.calories, goal.calories), in: 0...max(goal.calories, 1)) { EmptyView() }
                                .gaugeStyle(.linearCapacity)
                                .tint(NorthColor.signal)
                        }
                        MacroRow(macros: log.totals, goal: log.progress?.goal)
                        if let summary = log.progress?.summary { Text(summary).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    if log.progress == nil {
                        Text("Set a macro goal in Settings → Body & Goal to see how today compares.")
                    } else if let recommendation = log.progress?.recommendation {
                        Text(recommendation)
                    }
                }
                Section("Eaten") {
                    if log.entries.isEmpty { Text("Nothing logged yet today.").foregroundStyle(.secondary) }
                    ForEach(log.entries, id: \.id) { entry in
                        LabeledContent {
                            Text("\(Int(entry.macros.calories)) kcal").monospacedDigit()
                        } label: {
                            Text(entry.label)
                            if let grams = entry.quantityGrams { Text("\(Int(grams)) g") }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await run { try await service.deleteEntry(entry.id) } } }
                        }
                    }
                    Button("Log Food", systemImage: "plus") { adding = true }
                }
            } else if error == nil {
                ProgressView()
            }
        }
        .sheet(isPresented: $adding) {
            LogFoodSheet(service: service) { newLog in log = newLog }
        }
        .task { await run { try await service.log() } }
        .refreshable { await run { try await service.log() } }
    }

    private func run(_ load: () async throws -> FoodLog) async {
        do { log = try await load(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct MacroRow: View {
    let macros: Macros
    let goal: Macros?

    var body: some View {
        HStack(spacing: 24) {
            item("PROTEIN", macros.proteinG, goal?.proteinG)
            item("FAT", macros.fatG, goal?.fatG)
            item("CARBS", macros.carbG, goal?.carbG)
        }
    }

    private func item(_ label: String, _ value: Double, _ target: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(target.map { "\(Int(value))/\(Int($0)) g" } ?? "\(Int(value)) g").font(.subheadline.monospacedDigit())
            Text(label).font(.caption2.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
        }
    }
}

/// Log an ingredient by weight, or a whole meal from a plan.
private struct LogFoodSheet: View {
    let service: NutritionServicing
    let onLogged: (FoodLog) -> Void

    @State private var query = ""
    @State private var results: [Ingredient] = []
    @State private var meals: [(plan: String, id: String, name: String, kcal: Double)] = []
    @State private var picked: Ingredient?
    @State private var grams = 100.0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorRow(error) }
                if let picked {
                    Section(picked.name) {
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...2000, step: 5)
                        LabeledContent("Calories", value: "\(Int(picked.per100g.calories * grams / 100)) kcal")
                        Button("Log It") { log { try await service.logFood(picked.id, grams: grams) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if !meals.isEmpty, query.isEmpty {
                    Section("From Your Plans") {
                        ForEach(meals, id: \.id) { meal in
                            Button { log { try await service.logMeal(meal.id) } } label: {
                                LabeledContent("\(meal.plan) · \(meal.name)", value: "\(Int(meal.kcal)) kcal")
                            }
                        }
                    }
                }
                Section("Ingredients") {
                    ForEach(results, id: \.id) { ingredient in
                        Button {
                            picked = ingredient
                            grams = ingredient.servingSizeGrams > 0 ? ingredient.servingSizeGrams : 100
                        } label: {
                            LabeledContent(ingredient.name, value: "\(Int(ingredient.per100g.calories)) kcal/100 g")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search ingredients")
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                do { results = try await service.ingredients(matching: query) } catch { self.error = error.localizedDescription }
            }
            .task { await loadMeals() }
        }
    }

    private func loadMeals() async {
        do {
            var out: [(plan: String, id: String, name: String, kcal: Double)] = []
            for summary in try await service.plans() {
                let plan = try await service.plan(summary.id)
                out += plan.value2.meals.map { (plan.value1.name, $0.id, $0.name, $0.totalMacros.calories) }
            }
            meals = out
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func log(_ action: @escaping () async throws -> FoodLog) {
        Task {
            do { onLogged(try await action()); dismiss() } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Plans

private struct MealPlansView: View {
    let service: NutritionServicing
    @State private var plans: [MealPlanSummary] = []
    @State private var error: String?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            ForEach(plans, id: \.id) { plan in
                NavigationLink {
                    MealPlanView(id: plan.id, service: service)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                        Text("\(plan.mealCount) meals · \(Int(plan.totalMacros.calories)) kcal").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        Task {
                            do { try await service.deletePlan(plan.id); await load() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            Button("New Plan", systemImage: "plus") { naming = true }
        }
        .alert("New Meal Plan", isPresented: $naming) {
            TextField("e.g. Training days", text: $newName)
            Button("Create") {
                let name = newName
                newName = ""
                Task {
                    do { _ = try await service.createPlan(name: name); await load() } catch { self.error = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { plans = try await service.plans(); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct MealPlanView: View {
    let id: String
    let service: NutritionServicing
    @State private var plan: MealPlanDetail?
    @State private var error: String?
    @State private var addingMeal = false
    @State private var mealName = ""
    @State private var portionFor: String?

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            if let plan {
                Section {
                    MacroRow(macros: plan.value1.totalMacros, goal: nil)
                    LabeledContent("Calories", value: "\(Int(plan.value1.totalMacros.calories)) kcal")
                }
                ForEach(plan.value2.meals, id: \.id) { meal in
                    Section {
                        ForEach(meal.ingredients, id: \.id) { portion in
                            LabeledContent("\(portion.name) · \(Int(portion.quantityGrams)) g", value: "\(Int(portion.macros.calories)) kcal")
                                .swipeActions {
                                    Button("Remove", role: .destructive) { act { try await service.removePortion(portion.id) } }
                                }
                        }
                        Button("Add Ingredient", systemImage: "plus") { portionFor = meal.id }
                    } header: {
                        HStack {
                            Text("\(meal.mealNumber). \(meal.name) · \(Int(meal.totalMacros.calories)) kcal")
                            Spacer()
                            Button("Remove Meal", systemImage: "trash") { act { try await service.removeMeal(meal.id) } }
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                Button("Add a Meal", systemImage: "plus") { addingMeal = true }
            } else if error == nil {
                ProgressView()
            }
        }
        .navigationTitle(plan?.value1.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .alert("New Meal", isPresented: $addingMeal) {
            TextField("e.g. Breakfast", text: $mealName)
            Button("Add") {
                let name = mealName
                mealName = ""
                act { _ = try await service.addMeal(to: id, name: name, number: (plan?.value2.meals.count ?? 0) + 1) }
            }
            Button("Cancel", role: .cancel) { mealName = "" }
        }
        .sheet(item: Binding(get: { portionFor.map(MealRef.init) }, set: { portionFor = $0?.id })) { ref in
            PortionSheet(service: service) { ingredientID, grams in
                try await service.addPortion(to: ref.id, ingredientID: ingredientID, grams: grams)
                await load()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do { plan = try await service.plan(id); error = nil } catch { self.error = error.localizedDescription }
    }

    private func act(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action(); await load() } catch { self.error = error.localizedDescription }
        }
    }
}

private struct MealRef: Identifiable {
    let id: String
}

private struct PortionSheet: View {
    let service: NutritionServicing
    let onAdd: (String, Double) async throws -> Void
    @State private var query = ""
    @State private var results: [Ingredient] = []
    @State private var picked: Ingredient?
    @State private var grams = 100.0
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let error { ErrorRow(error) }
                if let picked {
                    Section(picked.name) {
                        Stepper("\(Int(grams)) g", value: $grams, in: 5...2000, step: 5)
                        Button("Add") {
                            Task {
                                do { try await onAdd(picked.id, grams); dismiss() } catch { self.error = error.localizedDescription }
                            }
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
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                do { results = try await service.ingredients(matching: query) } catch { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Ingredients

private struct IngredientsView: View {
    let service: NutritionServicing
    @State private var query = ""
    @State private var results: [Ingredient] = []
    @State private var error: String?
    @State private var adding = false

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            ForEach(results, id: \.id) { ingredient in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(ingredient.name)
                        if ingredient.own { Text("YOURS").font(.caption2.weight(.medium)).tracking(1.5).foregroundStyle(NorthColor.signal) }
                    }
                    let m = ingredient.per100g
                    Text("\(Int(m.calories)) kcal · P \(Int(m.proteinG)) · F \(Int(m.fatG)) · C \(Int(m.carbG)) per 100 g")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    if ingredient.own {
                        Button("Delete", role: .destructive) {
                            Task {
                                do { try await service.deleteIngredient(ingredient.id); await search() } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search ingredients")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Add Ingredient", systemImage: "plus") { adding = true } }
        }
        .sheet(isPresented: $adding) {
            IngredientForm { name, macros in
                try await service.createIngredient(name: name, per100g: macros)
                await search()
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private func search() async {
        do { results = try await service.ingredients(matching: query); error = nil } catch { self.error = error.localizedDescription }
    }
}

private struct IngredientForm: View {
    let onSave: (String, Macros) async throws -> Void
    @State private var name = ""
    // Empty until typed: a field showing 0 took typing in front of the 0,
    // so "380" became 3800.
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var fat: Double?
    @State private var carbs: Double?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section("Per 100 g") {
                    number("Calories (kcal)", $calories)
                    number("Protein (g)", $protein)
                    number("Fat (g)", $fat)
                    number("Carbs (g)", $carbs)
                }
                if let error { ErrorRow(error) }
            }
            .navigationTitle("New Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await onSave(name, .init(calories: calories ?? 0, proteinG: protein ?? 0,
                                                             fatG: fat ?? 0, carbG: carbs ?? 0))
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || calories == nil)
                }
            }
        }
    }

    private func number(_ label: String, _ value: Binding<Double?>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }
}
