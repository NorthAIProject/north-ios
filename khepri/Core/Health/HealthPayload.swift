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

/// Everything one sync reads from Apple Health.
struct HealthSnapshot {
    var steps: [DailyValue] = []
    var activeEnergy: [DailyValue] = []
    var restingHeartRate: [DailyValue] = []
    var hrv: [DailyValue] = []
    /// Minutes asleep, keyed by the day the night ends.
    var sleep: [DailyValue] = []
    var workouts: [HealthWorkoutRecord] = []
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
        daily(snapshot.sleep, "sleep_asleep", "min")

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
