import Foundation
import HealthKit
import NorthAPI

typealias HealthSyncRequest = Components.Schemas.HealthSyncRequest
typealias HealthReadingPayload = Components.Schemas.HealthReading
typealias HealthWorkoutPayload = Components.Schemas.HealthWorkout

/// One day's figure: a total (steps, active energy) or an average (resting
/// heart rate, HRV). `day` is the start of the day in the account's calendar.
struct DailyValue: Equatable {
    var day: Date
    var value: Double
}

/// A workout as Apple Health recorded it, before translation.
struct HealthWorkoutRecord: Equatable {
    var id: UUID
    var type: HKWorkoutActivityType
    var start: Date
    var end: Date
    var kilocalories: Double?
    var meters: Double?
    var indoor: Bool
}

/// One stretch of a single sleep stage, as a watch or sleep app recorded it.
struct SleepStageBlock: Equatable {
    enum Stage: String { case deep, rem, core, awake }
    var stage: Stage
    var start: Date
    var end: Date
}

/// Everything one sync reads from Apple Health.
struct HealthSnapshot {
    var steps: [DailyValue] = []
    var activeEnergy: [DailyValue] = []
    var restingHeartRate: [DailyValue] = []
    var hrv: [DailyValue] = []
    /// Apple Watch's daily VO2 max estimate in ml/kg/min, where there is one.
    var vo2Max: [DailyValue] = []
    /// Minutes asleep, keyed by the day the night ends.
    var sleep: [DailyValue] = []
    var workouts: [HealthWorkoutRecord] = []

    // My Day. Daily totals unless noted.
    var exerciseMinutes: [DailyValue] = []
    var standHours: [DailyValue] = []
    var daylightMinutes: [DailyValue] = []
    /// Food and water other apps logged. What this app wrote is left out at
    /// the query, because the server already has it as a log of its own.
    var dietaryWater: [DailyValue] = []
    var dietaryEnergy: [DailyValue] = []
    var dietaryProtein: [DailyValue] = []
    var dietaryCarbs: [DailyValue] = []
    var dietaryFat: [DailyValue] = []
    /// The day's last weighing.
    var bodyMass: [DailyValue] = []
    var sleepStages: [SleepStageBlock] = []
    /// Vitamins other apps logged from food, per day, in each vitamin's usual
    /// unit. Only whether there was any counts toward coverage.
    var vitaminA: [DailyValue] = []
    var vitaminC: [DailyValue] = []
    var vitaminD: [DailyValue] = []
    var bloodPressure: [BloodPressureReading] = []
}

/// One cuff reading as Apple Health stores it: a correlation of two samples.
struct BloodPressureReading: Equatable {
    var at: Date
    var systolic: Double
    var diastolic: Double
}

/// Turns a snapshot into the requests `POST /health/samples` takes.
///
/// Every reading is one day's aggregate starting at that day's start, which
/// is the server's upsert key: re-sending a day replaces it. That is what lets
/// each sync re-read the last few days (today's steps keep growing, and a
/// watch delivers late) without storing anything twice.
enum HealthPayload {
    /// Readings per request. Months of daily aggregates fit in one; the bound
    /// exists for a first sync reaching far back.
    static let batchSize = 2000

    static func requests(from snapshot: HealthSnapshot, calendar: Calendar) -> [HealthSyncRequest] {
        var readings: [HealthReadingPayload] = []
        func daily(_ values: [DailyValue], _ metric: String, _ unit: String) {
            for v in values where v.value > 0 {
                let end = calendar.date(byAdding: .day, value: 1, to: v.day) ?? v.day
                readings.append(.init(metric: metric, value: v.value, unit: unit, startedAt: v.day, endedAt: end))
            }
        }
        daily(snapshot.steps, "steps", "count")
        daily(snapshot.activeEnergy, "active_calories", "kcal")
        daily(snapshot.restingHeartRate, "resting_heart_rate", "count/min")
        daily(snapshot.hrv, "hrv_sdnn", "ms")
        daily(snapshot.vo2Max, "vo2max", "ml/kg/min")
        daily(snapshot.sleep, "sleep_asleep", "min")
        daily(snapshot.exerciseMinutes, "exercise_minutes", "min")
        daily(snapshot.standHours, "stand_hours", "count")
        daily(snapshot.daylightMinutes, "time_in_daylight", "min")
        daily(snapshot.dietaryWater, "dietary_water", "ml")
        daily(snapshot.dietaryEnergy, "dietary_energy", "kcal")
        daily(snapshot.dietaryProtein, "dietary_protein", "g")
        daily(snapshot.dietaryCarbs, "dietary_carbs", "g")
        daily(snapshot.dietaryFat, "dietary_fat", "g")
        daily(snapshot.vitaminA, "dietary_vitamin_a", "mcg")
        daily(snapshot.vitaminC, "dietary_vitamin_c", "mg")
        daily(snapshot.vitaminD, "dietary_vitamin_d", "mcg")
        // Each reading is an instant, two metrics at the same moment.
        for bp in snapshot.bloodPressure where bp.systolic > 0 && bp.diastolic > 0 {
            readings.append(.init(metric: "bp_systolic", value: bp.systolic, unit: "mmHg", startedAt: bp.at))
            readings.append(.init(metric: "bp_diastolic", value: bp.diastolic, unit: "mmHg", startedAt: bp.at))
        }
        // A weighing is an instant, and the day's start keeps one per day.
        for v in snapshot.bodyMass where v.value > 0 {
            readings.append(.init(metric: "body_mass", value: v.value, unit: "kg", startedAt: v.day))
        }
        // One reading per block, its start being the server's upsert key, so a
        // re-read night replaces itself.
        for b in snapshot.sleepStages where b.end > b.start {
            let minutes = (b.end.timeIntervalSince(b.start) / 60 * 10).rounded() / 10
            readings.append(.init(metric: "sleep_\(b.stage.rawValue)", value: minutes, unit: "min",
                                  startedAt: b.start, endedAt: b.end))
        }

        let workouts = snapshot.workouts.compactMap(workout)

        var out: [HealthSyncRequest] = []
        var start = 0
        repeat {
            let slice = Array(readings[start..<min(start + batchSize, readings.count)])
            // Workouts ride with the first batch; later batches are readings only.
            let batchWorkouts = start == 0 ? workouts : []
            if !slice.isEmpty || !batchWorkouts.isEmpty {
                out.append(.init(readings: slice, workouts: batchWorkouts))
            }
            start += batchSize
        } while start < readings.count
        return out
    }

    static func workout(_ w: HealthWorkoutRecord) -> HealthWorkoutPayload? {
        let hours = w.end.timeIntervalSince(w.start) / 3600
        guard hours > 0 else { return nil }
        let kmh = w.meters.map { $0 / 1000 / hours }
        guard let code = HealthActivityMapping.code(for: w.type, kmh: kmh, indoor: w.indoor) else { return nil }
        return .init(activityCode: code, externalId: w.id.uuidString, startedAt: w.start, endedAt: w.end,
                     calories: (w.kilocalories ?? 0) > 0 ? w.kilocalories : nil)
    }
}

/// Minutes asleep per night from Apple Health's sleep samples.
///
/// A night is usually recorded by more than one device (the watch, the phone,
/// a sleep app), and their samples overlap. Adding them would double the
/// night, so the intervals are merged first. A night belongs to the day it
/// ends: a sleep from 23:00 to 07:00 is that morning's.
enum SleepNights {
    static func minutes(asleep intervals: [DateInterval], calendar: Calendar) -> [DailyValue] {
        let merged = merge(intervals)
        var byDay: [Date: Double] = [:]
        for interval in merged {
            byDay[calendar.startOfDay(for: interval.end), default: 0] += interval.duration / 60
        }
        return byDay.keys.sorted().map { DailyValue(day: $0, value: (byDay[$0]! * 10).rounded() / 10) }
    }

    static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var out: [DateInterval] = []
        for next in sorted {
            if let last = out.last, next.start <= last.end {
                out[out.count - 1] = DateInterval(start: last.start, end: max(last.end, next.end))
            } else {
                out.append(next)
            }
        }
        return out
    }
}

/// Sleep stages from Apple Health's samples.
///
/// Unlike the total, stages cannot be merged across devices: a watch saying
/// "deep" and a phone saying "core" for the same minute do not add up to
/// anything. So each night takes the stages from the one source that recorded
/// the most staged time — in practice, the watch — and contiguous blocks of
/// the same stage are joined.
enum SleepStages {
    struct Sample: Equatable {
        var stage: SleepStageBlock.Stage
        var start: Date
        var end: Date
        var source: String
    }

    static func blocks(from samples: [Sample], calendar: Calendar) -> [SleepStageBlock] {
        var byNight: [Date: [Sample]] = [:]
        for s in samples { byNight[calendar.startOfDay(for: s.end), default: []].append(s) }

        var out: [SleepStageBlock] = []
        for night in byNight.keys.sorted() {
            let samples = byNight[night]!
            var staged: [String: TimeInterval] = [:]
            for s in samples { staged[s.source, default: 0] += s.end.timeIntervalSince(s.start) }
            guard let primary = staged.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key else { continue }

            let mine = samples.filter { $0.source == primary }.sorted { $0.start < $1.start }
            for s in mine {
                if let last = out.last, last.stage == s.stage, s.start <= last.end {
                    out[out.count - 1].end = max(last.end, s.end)
                } else {
                    out.append(SleepStageBlock(stage: s.stage, start: s.start, end: s.end))
                }
            }
        }
        return out
    }

    /// The stage a sleep-analysis value names, or nil for in-bed and the
    /// unspecified "asleep" older devices report.
    static func stage(for value: Int) -> SleepStageBlock.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .asleepCore: .core
        case .awake: .awake
        default: nil
        }
    }
}
