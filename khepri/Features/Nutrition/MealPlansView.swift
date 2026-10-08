import NorthAPI
import NorthKit
import SwiftUI

/// The person's meal plans, and making a new one.
struct MealPlansView: View {
    let service: NutritionServicing
    @State private var plans: [MealPlanSummary] = []
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        List {
            if let error { ErrorRow(error) }
            ForEach(plans, id: \.id) { plan in
                NavigationLink {
                    MealPlanView(store: MealPlanStore(id: plan.id, service: service), service: service)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                        Text("\(plan.planType.title) · \(plan.dayCount == 1 ? "1 day" : "\(plan.dayCount) days") · \(plan.mode.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            Button("New Plan", systemImage: "plus") { creating = true }
        }
        .sheet(isPresented: $creating, onDismiss: { Task { await load() } }) {
            NewPlanSheet(service: service)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do { plans = try await service.plans(); error = nil } catch { self.error = error.localizedDescription }
    }
}

/// A new plan: easy takes a carb level and a number of days, advanced also a
/// custom carb share and chosen weekdays. Shares and grams come from the
/// server's plan options, worked out from the person's macro target.
private struct NewPlanSheet: View {
    let service: NutritionServicing
    @State private var options: MealPlanOptions?
    @State private var name = ""
    @State private var mode = MealPlanMode.easy
    @State private var planType = MealPlanType.midCarb
    @State private var customPct = 40.0
    @State private var dayCount = 7
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let error { ErrorRow(error) }
                if let options {
                    if let target = options.target {
                        Section("Your daily target") { TargetRow(target: target) }
                        form(options)
                    } else {
                        Section {
                            NavigationLink("Work out your macro target") { BodyAndGoalScreen() }
                        } footer: {
                            Text("Meal plans are built on the daily target from Body & Goal.")
                        }
                    }
                } else if error == nil {
                    ProgressView()
                }
            }
            .navigationTitle("New Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!canCreate)
                }
            }
            .task { await loadOptions() }
            // Reloaded on the way back from Body & Goal, where a target may
            // just have been worked out.
            .onAppear { if options?.target == nil { Task { await loadOptions() } } }
        }
    }

    @ViewBuilder
    private func form(_ options: MealPlanOptions) -> some View {
        Section {
            TextField("Name, e.g. Training weeks", text: $name)
            Picker("Mode", selection: $mode) {
                Text("Easy").tag(MealPlanMode.easy)
                Text("Advanced").tag(MealPlanMode.advanced)
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(mode == .easy
                ? "Pick a carb level and a number of days. Every day gets the same target, and nothing can go over it."
                : "Choose weekdays and a custom carb share; each day can get its own target, and you can go over once you confirm.")
        }
        Section("Carbs") {
            Picker("Plan type", selection: $planType) {
                ForEach(options.planTypes.filter { !$0.advancedOnly || mode == .advanced }, id: \.id) { option in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.id.title)
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(option.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if planType == .custom {
                Stepper("\(Int(customPct))% of your carbs", value: $customPct, in: 0...100, step: 5)
            }
        }
        .onChange(of: mode) { _, mode in if mode == .easy, planType == .custom { planType = .midCarb } }
        if mode == .easy {
            Section {
                Stepper(dayCount == 1 ? "1 day" : "\(dayCount) days", value: $dayCount, in: 1...options.maxDays)
            } footer: {
                Text("Days start on Monday.")
            }
        } else {
            Section("Weekdays") {
                ForEach(MealPlanDay.mondayFirst, id: \.self) { weekday in
                    Toggle(Calendar.current.standaloneWeekdaySymbols[weekday], isOn: Binding(
                        get: { weekdays.contains(weekday) },
                        set: { isOn in if isOn { weekdays.insert(weekday) } else { weekdays.remove(weekday) } }
                    ))
                }
            }
        }
    }

    private var canCreate: Bool {
        options?.target != nil && !saving && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode == .easy || !weekdays.isEmpty)
    }

    private func loadOptions() async {
        do { options = try await service.planOptions(); error = nil } catch { self.error = error.localizedDescription }
    }

    private func create() async {
        saving = true
        defer { saving = false }
        let request = MealPlanRequest(
            name: name, planType: planType, customCarbPct: planType == .custom ? customPct : nil, mode: mode,
            dayCount: mode == .easy ? dayCount : nil,
            weekdays: mode == .advanced ? MealPlanDay.mondayFirst.filter(weekdays.contains) : nil
        )
        do { _ = try await service.createPlan(request); dismiss() } catch { self.error = error.localizedDescription }
    }
}

/// A macro target in one line: calories, then grams of each macro.
struct TargetRow: View {
    let target: Macros

    var body: some View {
        Text("\(Int(target.calories)) kcal · \(Int(target.proteinG)) g protein · \(Int(target.carbG)) g carbs · \(Int(target.fatG)) g fat")
            .font(.subheadline.monospacedDigit())
    }
}

extension Components.Schemas.MealPlanTypeOption {
    /// "26–45% of your carbs · about 92 g a day".
    var detail: String {
        var text = "\(Int(minPct))–\(Int(maxPct))% of your carbs"
        if let grams = defaultCarbG { text += " · about \(Int(grams.rounded())) g a day" }
        return text
    }
}

extension MealPlanType {
    var title: String {
        switch self {
        case .noCarb: "No carb"
        case .lowCarb: "Low carb"
        case .midCarb: "Mid carb"
        case .highCarb: "High carb"
        case .custom: "Custom"
        }
    }
}

extension MealPlanMode {
    var title: String { self == .easy ? "Easy" : "Advanced" }
}
