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
                LabeledContent {
                    TextField("Weight", value: $weight, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                } label: {
                    imperial ? Text("Weight (lb)") : Text("Weight (kg)")
                }
                LabeledContent {
                    TextField("Height", value: $height, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                } label: {
                    imperial ? Text("Height (in)") : Text("Height (cm)")
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
                    Button { Task { await generate() } } label: {
                        calculator?.goal == nil ? Text("Work Out My Goal") : Text("Work It Out Again")
                    }
                        .disabled(saving)
                } header: {
                    Text("Macro Goal")
                }
                if let current = calculator?.goal {
                    Section {
                        LabeledContent("Calories", value: String(localized: "\(Int(current.calorieGoal)) kcal"))
                        LabeledContent("Protein", value: String(localized: "\(Int(current.proteinG)) g"))
                        LabeledContent("Fat", value: String(localized: "\(Int(current.fatG)) g"))
                        LabeledContent("Carbs", value: String(localized: "\(Int(current.carbG)) g"))
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

    /// The display name of a calculator option; the key is the server's. A
    /// key this build does not know shows as itself, tidied.
    private func label(_ key: String) -> String {
        switch key {
        case "sedentary": String(localized: "Sedentary")
        case "light": String(localized: "Light", comment: "Activity level")
        case "moderate": String(localized: "Moderate", comment: "Activity level")
        case "heavy": String(localized: "Heavy", comment: "Activity level")
        case "extra_heavy": String(localized: "Extra Heavy", comment: "Activity level")
        case "cutting": String(localized: "Cutting", comment: "Body goal: losing fat")
        case "maintenance": String(localized: "Maintenance", comment: "Body goal: keeping weight")
        case "bulking": String(localized: "Bulking", comment: "Body goal: gaining muscle")
        case "high_carb": String(localized: "High Carb")
        case "moderate_carb": String(localized: "Moderate Carb")
        case "low_carb": String(localized: "Low Carb")
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
