import HealthKit

/// North's activity code for an Apple Health workout.
///
/// The server keeps one calorie table and every provider translates into it,
/// the way the Strava import does. Where the table grades by speed (running,
/// walking, cycling), the workout's own distance and duration pick the grade.
/// A workout type North has no equivalent for returns nil and is not synced:
/// guessing would put wrong calories in front of the coach.
enum HealthActivityMapping {
    static func code(for type: HKWorkoutActivityType, kmh: Double?, indoor: Bool) -> String? {
        switch type {
        case .running: running(kmh)
        case .walking: walking(kmh)
        case .cycling: indoor ? "cycling_stationary_moderate" : cycling(kmh)
        case .hiking: "hiking"
        case .swimming: "swimming_moderate"
        case .rowing: "rowing_moderate"
        case .elliptical: "elliptical"
        case .stairClimbing, .stairs: "stair_climbing"
        case .jumpRope: "jump_rope"
        case .highIntensityIntervalTraining, .mixedCardio: "hiit"
        case .dance, .socialDance, .cardioDance: "dancing"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "strength_training"
        case .coreTraining: "calisthenics"
        case .yoga: "yoga"
        case .pilates: "pilates"
        case .flexibility, .cooldown: "stretching"
        case .stepTraining: "step_aerobics"
        case .waterFitness: "water_aerobics"
        case .basketball: "basketball"
        case .soccer: "soccer"
        case .tennis: "tennis"
        case .tableTennis: "table_tennis"
        case .volleyball: "volleyball"
        case .baseball, .softball: "baseball_softball"
        case .golf: "golf"
        case .hockey: "ice_hockey"
        case .boxing: "boxing"
        case .kickboxing: "kickboxing"
        case .martialArts: "martial_arts"
        case .climbing: "climbing"
        case .downhillSkiing, .snowboarding: "skiing"
        case .crossCountrySkiing: "skiing_cross_country_moderate"
        case .surfingSports: "surfing"
        case .sailing: "sailing"
        case .paddleSports: "canoeing_moderate"
        case .equestrianSports: "horseback_riding"
        default: nil
        }
    }

    /// Thresholds sit between the table's grades (8, 9.8, 11.3, >13 km/h).
    private static func running(_ kmh: Double?) -> String {
        guard let kmh else { return "running_9_8kmh" }
        switch kmh {
        case ..<8.9: return "running_8kmh"
        case ..<10.5: return "running_9_8kmh"
        case ..<13: return "running_11_3kmh"
        default: return "running_fast"
        }
    }

    private static func walking(_ kmh: Double?) -> String {
        guard let kmh else { return "walking_moderate" }
        switch kmh {
        case ..<4: return "walking_slow"
        case ..<5.6: return "walking_moderate"
        default: return "walking_brisk"
        }
    }

    private static func cycling(_ kmh: Double?) -> String {
        guard let kmh else { return "cycling_moderate" }
        switch kmh {
        case ..<16: return "cycling_leisure"
        case ..<19: return "cycling_moderate"
        default: return "cycling_vigorous"
        }
    }
}
