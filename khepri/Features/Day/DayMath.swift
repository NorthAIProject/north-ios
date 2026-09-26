import NorthAPI
import NorthKit
import SwiftUI

/// The arithmetic behind My Day's drawings, kept out of the views so it can be
/// tested without rendering anything.
enum DayMath {
    static func fraction(_ value: Double, _ goal: Double) -> Double {
        goal > 0 ? min(max(value / goal, 0), 1) : 0
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : "\(h)h \(m)m"
    }

    static func activityRings(_ a: Components.Schemas.DayActivity) -> [RingValue] {
        [
            RingValue(id: "move", fraction: fraction(a.move.value, a.move.goal), color: NorthColor.Day.move),
            RingValue(id: "exercise", fraction: fraction(a.exercise.value, a.exercise.goal), color: NorthColor.Day.exercise),
            RingValue(id: "stand", fraction: fraction(a.stand.value, a.stand.goal), color: NorthColor.Day.stand),
        ]
    }

    /// Macro rings against the plan. Without a plan every ring reads empty
    /// rather than full: there is nothing to have met.
    static func macroRings(_ f: Components.Schemas.DayFood) -> [RingValue] {
        [
            RingValue(id: "protein", fraction: fraction(f.proteinG, f.goal?.proteinG ?? 0), color: NorthColor.Day.protein),
            RingValue(id: "carb", fraction: fraction(f.carbG, f.goal?.carbG ?? 0), color: NorthColor.Day.carb),
            RingValue(id: "fat", fraction: fraction(f.fatG, f.goal?.fatG ?? 0), color: NorthColor.Day.fat),
        ]
    }

    static let stageOrder = ["deep", "rem", "core", "awake"]

    static func stageName(_ stage: String) -> LocalizedStringKey {
        switch stage {
        case "deep": "Deep"
        case "rem": "REM"
        case "core": "Core"
        default: "Awake"
        }
    }

    static func stageColor(_ stage: String) -> Color {
        switch stage {
        case "deep": NorthColor.Day.sleep
        case "rem": NorthColor.Day.stand
        case "core": NorthColor.Day.water
        default: NorthColor.Day.move
        }
    }

    static func stageRow(_ stage: String) -> Int {
        switch stage {
        case "awake": 0
        case "rem": 1
        case "core": 2
        default: 3
        }
    }

    static func hypnogram(_ sleep: DaySleep) -> [Hypnogram.Block] {
        guard let start = sleep.blocks.map(\.start).min(), let end = sleep.blocks.map(\.end).max() else { return [] }
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return [] }
        return sleep.blocks.enumerated().map { index, block in
            let stage = block.stage.rawValue
            return Hypnogram.Block(
                id: index, row: stageRow(stage),
                start: block.start.timeIntervalSince(start) / total,
                width: block.end.timeIntervalSince(block.start) / total,
                color: stageColor(stage)
            )
        }
    }

    static func bmiName(_ c: Components.Schemas.DayBody.BmiCategoryPayload) -> LocalizedStringKey {
        switch c {
        case .underweight: "Underweight"
        case .healthy: "Healthy"
        case .overweight: "Overweight"
        case .obese: "Obese"
        }
    }

    static func bmiColor(_ c: Components.Schemas.DayBody.BmiCategoryPayload) -> Color {
        switch c {
        case .underweight: NorthColor.Day.water
        case .healthy: NorthColor.Day.food
        case .overweight: NorthColor.Day.fat
        case .obese: NorthColor.Day.move
        }
    }

    static func kindColor(_ kind: String) -> Color {
        switch kind {
        case "food": NorthColor.Day.food
        case "hydration": NorthColor.Day.water
        case "sleep": NorthColor.Day.sleep
        case "activity": NorthColor.Day.fat
        case "checkin", "habit": NorthColor.ember
        case "journal": NorthColor.agent
        default: NorthColor.signal
        }
    }

    struct TimelineRow: Identifiable {
        enum Kind {
            case entry(DayTimelineEntry)
            case marker(DayMarker)
            case now
        }

        let id: String
        let at: Date
        let kind: Kind
    }

    /// Entries, markers and the now line in one list, latest first — the
    /// order the web's rail reads top to bottom.
    static func timeline(_ day: DayResponse) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        for (i, e) in day.timeline.enumerated() { rows.append(TimelineRow(id: "e\(i)", at: e.at, kind: .entry(e))) }
        for (i, m) in day.markers.enumerated() { rows.append(TimelineRow(id: "m\(i)", at: m.at, kind: .marker(m))) }
        if day.isToday { rows.append(TimelineRow(id: "now", at: day.now, kind: .now)) }
        return rows.sorted { $0.at > $1.at }
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func phaseName(_ phase: Components.Schemas.DayFast.PhasePayload) -> String {
        switch phase {
        case .fed: String(localized: "Fed")
        case .fasting: String(localized: "Fasting")
        case .fatBurning: String(localized: "Fat burning")
        case .ketosis: String(localized: "Ketosis")
        }
    }

    static let nutrientNames: [String: String.LocalizationValue] = [
        "vitamin_a": "Vitamin A", "vitamin_b12": "Vitamin B12", "vitamin_c": "Vitamin C", "vitamin_d": "Vitamin D",
        "vitamin_e": "Vitamin E", "vitamin_k": "Vitamin K", "folate": "Folate", "calcium": "Calcium", "iron": "Iron",
        "magnesium": "Magnesium", "zinc": "Zinc", "potassium": "Potassium", "iodine": "Iodine", "omega3": "Omega-3",
        "fiber": "Fibre",
    ]

    static func nutrientName(_ key: String) -> String {
        nutrientNames[key].map { String(localized: $0) } ?? key
    }

    /// Body regions, head to foot, with the keys the server and the 3D body use.
    static let regions: [(key: String, name: String.LocalizationValue)] = [
        ("neck", "Neck"), ("shoulders", "Shoulders"), ("chest", "Chest"), ("upper_back", "Upper back"),
        ("lower_back", "Lower back"), ("abs", "Abs"), ("biceps", "Biceps"), ("triceps", "Triceps"),
        ("forearms", "Forearms"), ("hips", "Hips"), ("glutes", "Glutes"), ("quads", "Quads"),
        ("hamstrings", "Hamstrings"), ("knees", "Knees"), ("calves", "Calves"), ("feet", "Feet"),
    ]

    static func regionName(_ key: String) -> String {
        regions.first { $0.key == key }.map { String(localized: $0.name) } ?? key
    }

    static func severityName(_ severity: Int) -> String {
        switch severity {
        case 3: String(localized: "Painful")
        case 2: String(localized: "Sore")
        default: String(localized: "Stiff")
        }
    }

    /// Quick-add presets. The keys are the server's; the doses are shown only.
    static let caffeinePresets: [(key: String, name: String.LocalizationValue, mg: Int)] = [
        ("espresso", "Espresso", 63), ("coffee", "Coffee", 100), ("tea", "Tea", 45),
        ("energy_drink", "Energy drink", 80), ("cola", "Cola", 35),
    ]

    static let supplementPresets: [(key: String, name: String)] = [
        ("omega3", "Omega-3 (EPA/DHA)"), ("vitamin_d3", "Vitamin D3"), ("multivitamin", "Multivitamin"),
        ("magnesium", "Magnesium"), ("vitamin_c", "Vitamin C"), ("b12", "Vitamin B12"), ("iron", "Iron"),
        ("zinc", "Zinc"), ("calcium", "Calcium"), ("psyllium", "Psyllium husk"), ("creatine", "Creatine"),
    ]
}
