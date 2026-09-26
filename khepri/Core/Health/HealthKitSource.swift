import Foundation
import HealthKit

/// Reads what a sync sends. A protocol so the sync can be tested without
/// HealthKit, which the simulator has but a unit test cannot fill.
protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    func snapshot(from start: Date, to end: Date, calendar: Calendar) async throws -> HealthSnapshot
}

/// Apple Health through HealthKit's async query descriptors.
///
/// HealthKit never says whether reading was allowed. A refused type simply
/// returns nothing, so a person who allowed steps but not sleep syncs steps
/// and nothing else, with no error to show.
struct HealthKitSource: HealthDataSource {
    let store: HKHealthStore

    init(store: HKHealthStore = HealthStore.shared) {
        self.store = store
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func snapshot(from start: Date, to end: Date, calendar: Calendar) async throws -> HealthSnapshot {
        async let steps = daily(.stepCount, .count(), .cumulativeSum, start, end, calendar)
        async let energy = daily(.activeEnergyBurned, .kilocalorie(), .cumulativeSum, start, end, calendar)
        async let resting = daily(.restingHeartRate, .count().unitDivided(by: .minute()), .discreteAverage, start, end, calendar)
        async let hrv = daily(.heartRateVariabilitySDNN, .secondUnit(with: .milli), .discreteAverage, start, end, calendar)
        async let sleep = sleepMinutes(start, end, calendar)
        async let workouts = workouts(start, end)
        return try await HealthSnapshot(steps: steps, activeEnergy: energy, restingHeartRate: resting,
                                        hrv: hrv, sleep: sleep, workouts: workouts)
    }

    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ options: HKStatisticsOptions,
                       _ start: Date, _ end: Date, _ calendar: Calendar) async throws -> [DailyValue] {
        try await store.dailyValues(id, unit, options, from: start, to: end, calendar: calendar)
    }

    private func sleepMinutes(_ start: Date, _ end: Date, _ calendar: Calendar) async throws -> [DailyValue] {
        // A night ending on the first day began the evening before.
        let from = calendar.date(byAdding: .hour, value: -18, to: calendar.startOfDay(for: start)) ?? start
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let intervals = try await descriptor.result(for: store)
            .filter { asleep.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let startDay = calendar.startOfDay(for: start)
        return SleepNights.minutes(asleep: intervals, calendar: calendar).filter { $0.day >= startDay }
    }

    private func workouts(_ start: Date, _ end: Date) async throws -> [HealthWorkoutRecord] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let own = HKSource.default()
        return try await descriptor.result(for: store)
            // A workout this app wrote is already a session on the server.
            .filter { $0.sourceRevision.source != own }
            .map { w in
                HealthWorkoutRecord(
                    id: w.uuid, type: w.workoutActivityType, start: w.startDate, end: w.endDate,
                    kilocalories: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                    meters: distance(of: w),
                    indoor: w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
                )
            }
    }

    private func distance(of workout: HKWorkout) -> Double? {
        let kinds: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for kind in kinds {
            if let meters = workout.statistics(for: HKQuantityType(kind))?.sumQuantity()?.doubleValue(for: .meter()), meters > 0 {
                return meters
            }
        }
        return nil
    }
}

extension HKHealthStore {
    /// One figure per day: a sum for counts like steps, an average for rates
    /// like heart rate. Days with nothing recorded are left out.
    func dailyValues(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ options: HKStatisticsOptions,
                     from start: Date, to end: Date, calendar: Calendar) async throws -> [DailyValue] {
        let from = calendar.startOfDay(for: start)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: end)),
            options: options,
            anchorDate: from,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: self)
        return collection.statistics().compactMap { stats in
            let quantity = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            guard let value = quantity?.doubleValue(for: unit), value > 0 else { return nil }
            return DailyValue(day: stats.startDate, value: (value * 10).rounded() / 10)
        }
    }
}

/// One store for the app. HealthKit recommends a single long-lived instance.
enum HealthStore {
    static let shared = HKHealthStore()
}
