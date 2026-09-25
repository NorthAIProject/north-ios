import NorthAPI
import NorthKit
import SwiftUI

typealias Calculator = Components.Schemas.Calculator

protocol CalculatorServicing: Sendable {
    func calculator() async throws -> Calculator
    func record(_ request: Components.Schemas.BiometricsRequest) async throws -> Calculator
    func generate(activityLevel: String, goal: String, split: String) async throws -> Calculator
}

struct CalculatorService: CalculatorServicing {
    var api: Client = API.shared

    func calculator() async throws -> Calculator { try await NorthAPI.call { try await api.getCalculator().ok.body.json } }
    func record(_ request: Components.Schemas.BiometricsRequest) async throws -> Calculator {
        try await NorthAPI.call { try await api.recordBiometrics(body: .json(request)).ok.body.json }
    }
    func generate(activityLevel: String, goal: String, split: String) async throws -> Calculator {
        try await NorthAPI.call {
            try await api.generateMacroGoal(body: .json(.init(activityLevel: activityLevel, goal: goal, macroSplit: split))).created.body.json
        }
    }
}

/// Body measurements and the macro goal worked out from them. Workout
/// calories and the nutrition log both read these. Shown in the units chosen
/// in Settings; the server stores metric.
struct BodyAndGoalScreen: View {
    var service: CalculatorServicing = CalculatorService()
    var settings: SettingsServicing = SettingsService()

    @State private var calculator: Calculator?
    @State private var imperial = false
    @State private var weight = 70.0
    @State private var height = 170.0
    @State private var birth = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var sex = "female"
    @State private var activity = "moderate"
    @State private var goal = "maintenance"
    @State private var split = "moderate_carb"
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        Form {
            if let error { ErrorRow(error) }
            Section {
                LabeledContent(imperial ? "Weight (lb)" : "Weight (kg)") {
                    TextField("Weight", value: $weight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent(imperial ? "Height (in)" : "Height (cm)") {
                    TextField("Height", value: $height, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                DatePicker("Born", selection: $birth, displayedComponents: .date)
                Picker("Sex", selection: $sex) {
                    Text("Female").tag("female")
                    Text("Male").tag("male")
                }
                Button("Save Measurements") { Task { await saveBiometrics() } }
                    .disabled(saving)
            } header: {
                Text("Body")
            } footer: {
                Text("Used for workout calories and your macro goal.")
            }

            if let options = calculator?.options, calculator?.biometrics != nil {
                Section {
                    Picker("Activity", selection: $activity) { ForEach(options.activityLevels, id: \.self) { Text(label($0)).tag($0) } }
                    Picker("Goal", selection: $goal) { ForEach(options.goals, id: \.self) { Text(label($0)).tag($0) } }
                    Picker("Split", selection: $split) { ForEach(options.macroSplits, id: \.self) { Text(label($0)).tag($0) } }
                    Button(calculator?.goal == nil ? "Work Out My Goal" : "Work It Out Again") { Task { await generate() } }
                        .disabled(saving)
                } header: {
                    Text("Macro Goal")
                }
                if let current = calculator?.goal {
                    Section {
                        LabeledContent("Calories", value: "\(Int(current.calorieGoal)) kcal")
                        LabeledContent("Protein", value: "\(Int(current.proteinG)) g")
                        LabeledContent("Fat", value: "\(Int(current.fatG)) g")
                        LabeledContent("Carbs", value: "\(Int(current.carbG)) g")
                    } footer: {
                        Text("Maintenance is about \(Int(current.tdee)) kcal a day.")
                    }
                }
            }
        }
        .navigationTitle("Body & Goal")
        .task { await load() }
    }

    private func load() async {
        do {
            imperial = (try? await settings.preferences().unitsSystem) == .imperial
            let calc = try await service.calculator()
            apply(calc)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ calc: Calculator) {
        calculator = calc
        if let bio = calc.biometrics {
            weight = imperial ? (bio.weightKg * 2.20462).rounded() : bio.weightKg
            height = imperial ? (bio.heightCm / 2.54).rounded() : bio.heightCm
            birth = CalendarDay.date(from: bio.dateOfBirth) ?? birth
            sex = bio.sex
        }
        if let current = calc.goal {
            activity = current.activityLevel
            goal = current.goal
            split = current.macroSplit
        }
    }

    private func saveBiometrics() async {
        saving = true
        defer { saving = false }
        let kg = imperial ? weight / 2.20462 : weight
        let cm = imperial ? height * 2.54 : height
        do {
            apply(try await service.record(.init(weightKg: kg, heightCm: cm, dateOfBirth: CalendarDay.string(from: birth), sex: sex)))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func generate() async {
        saving = true
        defer { saving = false }
        do { apply(try await service.generate(activityLevel: activity, goal: goal, split: split)); error = nil } catch { self.error = error.localizedDescription }
    }

    private func label(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
