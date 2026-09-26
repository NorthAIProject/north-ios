import Foundation
import HealthKit

/// Reads what a sync sends. A protocol so the sync can be tested without
/// HealthKit, which the simulator has but a unit test cannot fill.
protocol HealthDataSource: Sendable {
    var isAvailable: Bool { get }
    func snapshot(from start: Date, to end: Date, calendar: Calendar) async throws -> HealthSnapshot {
        async let steps = daily(.stepCount, .count(), .cumulativeSum, start, end, calendar)
        async let energy = daily(.activeEnergyBurned, .kilocalorie(), .cumulativeSum, start, end, calendar)
        async let resting = daily(.restingHeartRate, .count().unitDivided(by: .minute()), .discreteAverage, start, end, calendar)
        async let hrv = daily(.heartRateVariabilitySDNN, .secondUnit(with: .milli), .discreteAverage, start, end, calendar)
        async let exercise = daily(.appleExerciseTime, .minute(), .cumulativeSum, start, end, calendar)
        async let daylight = daily(.timeInDaylight, .minute(), .cumulativeSum, start, end, calendar)
        async let water = daily(.dietaryWater, .literUnit(with: .milli), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let food = daily(.dietaryEnergyConsumed, .kilocalorie(), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let protein = daily(.dietaryProtein, .gram(), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let carbs = daily(.dietaryCarbohydrates, .gram(), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let fat = daily(.dietaryFatTotal, .gram(), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let weight = daily(.bodyMass, .gramUnit(with: .kilo), .mostRecent, start, end, calendar)
        async let vitaminA = daily(.dietaryVitaminA, .gramUnit(with: .micro), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let vitaminC = daily(.dietaryVitaminC, .gramUnit(with: .milli), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let vitaminD = daily(.dietaryVitaminD, .gramUnit(with: .micro), .cumulativeSum, start, end, calendar, excludingOwn: true)
        async let pressure = bloodPressure(start, end)
        async let stand = standHours(start, end, calendar)
        async let night = sleepNights(start, end, calendar)
        async let workouts = workouts(start, end)

        var snapshot = try await HealthSnapshot(steps: steps, activeEnergy: energy, restingHeartRate: resting,
                                                hrv: hrv, sleep: night.minutes, workouts: workouts)
        snapshot.exerciseMinutes = try await exercise
        snapshot.standHours = try await stand
        snapshot.daylightMinutes = try await daylight
        snapshot.dietaryWater = try await water
        snapshot.dietaryEnergy = try await food
        snapshot.dietaryProtein = try await protein
        snapshot.dietaryCarbs = try await carbs
        snapshot.dietaryFat = try await fat
        snapshot.bodyMass = try await weight
        snapshot.sleepStages = try await night.stages
        snapshot.vitaminA = try await vitaminA
        snapshot.vitaminC = try await vitaminC
        snapshot.vitaminD = try await vitaminD
        snapshot.bloodPressure = try await pressure
        return snapshot
    }

    /// Everything logged in a window, optionally leaving out what this app
    /// wrote itself (its water and caffeine are already logs on the server).
    private func predicate(_ start: Date, _ end: Date, excludingOwn: Bool) -> NSPredicate {
        let window = HKQuery.predicateForSamples(withStart: start, end: end)
        guard excludingOwn else { return window }
        let own = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: HKSource.default()))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [window, own])
    }

    private func daily(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ options: HKStatisticsOptions,
                       _ start: Date, _ end: Date, _ calendar: Calendar, excludingOwn: Bool = false) async throws -> [DailyValue] {
        let from = calendar.startOfDay(for: start)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate(from, end, excludingOwn: excludingOwn)),
            options: options,
            anchorDate: from,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        return collection.statistics().compactMap { stats in
            let quantity: HKQuantity? = if options.contains(.cumulativeSum) {
                stats.sumQuantity()
            } else if options.contains(.mostRecent) {
                stats.mostRecentQuantity()
            } else {
                stats.averageQuantity()
            }
            guard let value = quantity?.doubleValue(for: unit), value > 0 else { return nil }
            return DailyValue(day: stats.startDate, value: (value * 10).rounded() / 10)
        }
    }

    /// Cuff readings. Apple Health keeps each as a correlation of a systolic
    /// and a diastolic sample taken together.
    private func bloodPressure(_ start: Date, _ end: Date) async throws -> [BloodPressureReading] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.bloodPressure),
                                      predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let mmHg = HKUnit.millimeterOfMercury()
        return try await descriptor.result(for: store).compactMap { correlation in
            let sys = correlation.objects(for: HKQuantityType(.bloodPressureSystolic)).first as? HKQuantitySample
            let dia = correlation.objects(for: HKQuantityType(.bloodPressureDiastolic)).first as? HKQuantitySample
            guard let sys, let dia else { return nil }
            return BloodPressureReading(at: correlation.startDate, systolic: sys.quantity.doubleValue(for: mmHg),
                                        diastolic: dia.quantity.doubleValue(for: mmHg))
        }
    }

    /// Hours with a "stood" mark, per day. A category, so counted by hand.
    private func standHours(_ start: Date, _ end: Date, _ calendar: Calendar) async throws -> [DailyValue] {
        let from = calendar.startOfDay(for: start)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.appleStandHour),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        var byDay: [Date: Double] = [:]
        for sample in try await descriptor.result(for: store) where sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
            byDay[calendar.startOfDay(for: sample.startDate), default: 0] += 1
        }
        return byDay.keys.sorted().map { DailyValue(day: $0, value: byDay[$0]!) }
    }

    private func sleepNights(_ start: Date, _ end: Date, _ calendar: Calendar) async throws -> (minutes: [DailyValue], stages: [SleepStageBlock]) {
        // A night ending on the first day began the evening before.
        let from = calendar.date(byAdding: .hour, value: -18, to: calendar.startOfDay(for: start)) ?? start
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: from, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        let startDay = calendar.startOfDay(for: start)

        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let intervals = samples
            .filter { asleep.contains($0.value) }
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let minutes = SleepNights.minutes(asleep: intervals, calendar: calendar).filter { $0.day >= startDay }

        let staged = samples.compactMap { s -> SleepStages.Sample? in
            guard let stage = SleepStages.stage(for: s.value) else { return nil }
            return SleepStages.Sample(stage: stage, start: s.startDate, end: s.endDate,
                                      source: s.sourceRevision.source.bundleIdentifier)
        }
        let stages = SleepStages.blocks(from: staged, calendar: calendar).filter { calendar.startOfDay(for: $0.end) >= startDay }
        return (minutes, stages)
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

/// One store for the app. HealthKit recommends a single long-lived instance.
enum HealthStore {
    static let shared = HKHealthStore()
}
