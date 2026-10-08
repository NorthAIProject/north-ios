import NorthAPI
import NorthKit
import SwiftUI

/// One meal plan: each day against its target, its meals, and — in advanced
/// mode — each day's own target.
struct MealPlanView: View {
    @State var store: MealPlanStore
    let service: NutritionServicing

    @State private var sheet: Sheet?
    @State private var newMealDay: String?
    @State private var mealName = ""
    @State private var removingDay: MealPlanDay?
    @State private var choosingEasy = false

    enum Sheet: Identifiable {
        case portion(mealID: String)
        case speak(mealID: String)
        case day(String)
        case settings

        var id: String {
            switch self {
            case .portion(let id): "portion-\(id)"
            case .speak(let id): "speak-\(id)"
            case .day(let id): "day-\(id)"
            case .settings: "settings"
            }
        }
    }

    var body: some View {
        List {
            if let error = store.error { ErrorRow(error) }
            if let plan = store.plan {
                planSection(plan)
                ForEach(store.days, id: \.id) { day in daySection(day) }
                addDayRow
            } else if store.error == nil {
                ProgressView()
            }
        }
        .navigationTitle(store.plan?.value1.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .overagePrompt(store, active: sheet == nil)
        .alert("New Meal", isPresented: Binding(get: { newMealDay != nil }, set: { if !$0 { newMealDay = nil } })) {
            TextField("e.g. Breakfast", text: $mealName)
            Button("Add") {
                guard let dayID = newMealDay else { return }
                let name = mealName
                mealName = ""
                Task { await store.addMeal(to: dayID, name: name) }
            }
            Button("Cancel", role: .cancel) { mealName = "" }
        }
        .confirmationDialog(
            "Remove \(removingDay?.name ?? "")?", isPresented: Binding(get: { removingDay != nil }, set: { if !$0 { removingDay = nil } }),
            titleVisibility: .visible, presenting: removingDay
        ) { day in
            Button("Remove Day", role: .destructive) { Task { await store.removeDay(day.id) } }
        } message: { day in
            Text(day.meals.count == 1 ? "Its meal goes with it." : "Its \(day.meals.count) meals go with it.")
        }
        .confirmationDialog("Switch to Easy?", isPresented: $choosingEasy, titleVisibility: .visible) {
            ForEach(MealPlanType.presets, id: \.self) { type in
                Button(type == store.plan?.value1.planType ? "Keep \(type.title)" : type.title) {
                    Task { await store.switchToEasy(planType: type) }
                }
            }
        } message: {
            Text("Every day goes back to the plan's default target, and its own carbs, protein and fat are dropped. A day already over has to be trimmed first.")
        }
        .sheet(item: $sheet, onDismiss: { Task { await store.load() } }) { sheet in
            switch sheet {
            case .portion(let mealID): PortionSheet(store: store, service: service, mealID: mealID)
            case .speak(let mealID): SpeakMealSheet(store: store, service: service, mealID: mealID)
            case .day(let dayID): DayTargetSheet(store: store, dayID: dayID)
            case .settings: PlanSettingsSheet(store: store)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private func planSection(_ plan: MealPlanDetail) -> some View {
        Section {
            if let target = plan.value2.target {
                LabeledContent("Daily target") { TargetRow(target: target).foregroundStyle(.secondary) }
            } else {
                NavigationLink("Work out your macro target first") { BodyAndGoalScreen() }
            }
            LabeledContent("Carbs", value: plan.value1.planType.title + (plan.value1.customCarbPct.map { " · \(Int($0))%" } ?? ""))
            Button("Plan Settings") { sheet = .settings }
            if store.isAdvanced {
                Button("Switch to Easy…") { choosingEasy = true }
            } else {
                Button("Switch to Advanced") { Task { await store.switchToAdvanced() } }
            }
        } footer: {
            Text(store.isAdvanced
                ? "Advanced: each day can have its own target, and going over asks you to confirm."
                : "Easy: every day has the plan's target, and nothing can go over it.")
        }
        .disabled(!store.hasTarget)
    }

    private func daySection(_ day: MealPlanDay) -> some View {
        Section {
            if let status = day.status { DayStatusRows(status: status) }
            ForEach(day.meals, id: \.id) { meal in
                HStack {
                    Text(meal.name).font(.headline)
                    Spacer()
                    Text("\(Int(meal.totalMacros.calories)) kcal").foregroundStyle(.secondary).monospacedDigit()
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { Task { await store.removeMeal(meal.id) } }
                }
                ForEach(meal.ingredients, id: \.id) { portion in
                    LabeledContent("\(portion.name) · \(Int(portion.quantityGrams)) g", value: "\(Int(portion.macros.calories)) kcal")
                        .padding(.leading, 12)
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await store.removePortion(portion.id) } }
                        }
                }
                if store.hasTarget {
                    HStack(spacing: 16) {
                        Button("Add Ingredient", systemImage: "plus") { sheet = .portion(mealID: meal.id) }
                        Button("Say Ingredients", systemImage: "mic") { sheet = .speak(mealID: meal.id) }
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 12)
                }
            }
            Button("Add a Meal", systemImage: "plus") { newMealDay = day.id }
                .disabled(!store.hasTarget)
        } header: {
            HStack {
                Text(day.name)
                if let label = day.overrideLabel { Text("· \(label)") }
                Spacer()
                Menu("Day", systemImage: "ellipsis.circle") {
                    if store.isAdvanced && store.hasTarget {
                        Button("Change This Day's Target") { sheet = .day(day.id) }
                    }
                    if store.days.count > 1 {
                        Button("Remove Day", role: .destructive) {
                            if day.meals.isEmpty { Task { await store.removeDay(day.id) } } else { removingDay = day }
                        }
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var addDayRow: some View {
        let free = MealPlanDay.mondayFirst.filter { weekday in !store.days.contains { $0.weekday == weekday } }
        if let next = free.first {
            if store.isAdvanced {
                Menu("Add a Day", systemImage: "calendar.badge.plus") {
                    ForEach(free, id: \.self) { weekday in
                        Button(Calendar.current.standaloneWeekdaySymbols[weekday]) { Task { await store.addDay(weekday: weekday) } }
                    }
                }
            } else {
                Button("Add \(Calendar.current.standaloneWeekdaySymbols[next])", systemImage: "calendar.badge.plus") {
                    Task { await store.addDay(weekday: nil) }
                }
            }
        }
    }
}

/// A day's protein, carbs and fat against its target: how much is left, or
/// how far over.
private struct DayStatusRows: View {
    let status: MealDayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Protein", \.proteinG, NorthColor.Day.protein)
            row("Carbs", \.carbG, NorthColor.Day.carb)
            row("Fat", \.fatG, NorthColor.Day.fat)
        }
        .padding(.vertical, 4)
    }

    private func row(_ name: String, _ macro: KeyPath<Macros, Double>, _ tint: Color) -> some View {
        let consumed = status.consumed[keyPath: macro]
        let target = status.target[keyPath: macro]
        let over = status.over[keyPath: macro]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(over >= 0.5 ? "\(Int(consumed.rounded()))/\(Int(target.rounded())) g · \(Int(over.rounded())) g over"
                    : "\(Int(consumed.rounded()))/\(Int(target.rounded())) g · \(Int((target - consumed).rounded())) g left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(over >= 0.5 ? NorthColor.destructive : .secondary)
            }
            Gauge(value: min(consumed, max(target, 1)), in: 0...max(target, 1)) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(over >= 0.5 ? NorthColor.destructive : tint)
        }
    }
}

extension View {
    /// Shows a change the server refused for going over: by how much, per
    /// day, and — when the plan allows it — a way to save it anyway.
    /// `active` keeps a screen from presenting under a sheet that shows it.
    func overagePrompt(_ store: MealPlanStore, active: Bool, onSaved: @escaping () -> Void = {}) -> some View {
        modifier(OveragePrompt(store: store, active: active, onSaved: onSaved))
    }
}

private struct OveragePrompt: ViewModifier {
    let store: MealPlanStore
    let active: Bool
    let onSaved: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            "That would go over your target",
            isPresented: Binding(get: { active && store.pendingOverage != nil }, set: { if !$0 { store.pendingOverage = nil } }),
            presenting: store.pendingOverage
        ) { pending in
            if pending.overage.canConfirm {
                Button("Save Anyway", role: .destructive) {
                    Task {
                        await pending.resend()
                        if store.pendingOverage == nil && store.error == nil { onSaved() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { pending in
            Text(pending.overage.explanation)
        }
    }
}

extension MacroOverage {
    /// "Monday: 16 g over on carbs (94 of 78 g)", a line per day, and what
    /// to do about it.
    var explanation: String {
        let lines = days.map { day in
            let parts = [("protein", \Macros.proteinG), ("carbs", \Macros.carbG), ("fat", \Macros.fatG)]
                .filter { day.over[keyPath: $0.1] >= 0.5 }
                .map { name, macro in
                    "\(Int(day.over[keyPath: macro].rounded())) g over on \(name) (\(Int(day.consumed[keyPath: macro].rounded())) of \(Int(day.target[keyPath: macro].rounded())) g)"
                }
            return "\(Calendar.current.standaloneWeekdaySymbols[day.weekday]): \(parts.joined(separator: ", "))"
        }
        let advice = canConfirm ? "Save it anyway?" : "Easy plans stay within your target: choose less, remove something, or switch the plan to advanced."
        return (lines + [advice]).joined(separator: "\n")
    }
}

extension MealPlanType {
    /// The plan types with a fixed carb band; custom is advanced-only.
    static let presets: [MealPlanType] = [.noCarb, .lowCarb, .midCarb, .highCarb]
}

extension MealPlanDay {
    /// 0 is Sunday, as the server counts; days are shown Monday first.
    static let mondayFirst = [1, 2, 3, 4, 5, 6, 0]

    /// The day's own target in a few words, nil when it follows the plan.
    var overrideLabel: String? {
        var parts: [String] = []
        if let carbType { parts.append("\(carbType.title) day") } else if let carbG { parts.append("\(Int(carbG)) g carbs") }
        if let proteinG { parts.append("\(Int(proteinG)) g protein") }
        if let fatG { parts.append("\(Int(fatG)) g fat") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
