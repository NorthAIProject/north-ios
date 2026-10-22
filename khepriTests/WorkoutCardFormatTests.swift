import Foundation
import NorthAPI
import Testing

@testable import khepri

struct WorkoutCardFormatTests {
    private let en = Locale(identifier: "en")
    private let es = Locale(identifier: "es")

    private func exercise(_ name: String, sets: Int = 3, volume: Double = 900, best: String? = "60 kg × 6", pr: Bool = false) -> WorkoutExercise {
        WorkoutExercise(name: name, sets: sets, volumeKg: volume, best: best, pr: pr)
    }

    private func card(seconds: Int = 3600, distance: Double? = nil, sets: Int = 9, volume: Double = 3200.5, prs: Int = 1,
                      exercises: [WorkoutExercise] = []) -> WorkoutCard {
        WorkoutCard(sessionId: "s1", name: "Push day", activityCode: "strength_training_light",
                    startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 3600),
                    durationSeconds: seconds, distanceM: distance, sets: sets, volumeKg: volume, prs: prs, exercises: exercises)
    }

    @Test func aLiftingCardReadsTimeSetsAndVolume() {
        #expect(WorkoutCardFormat.stats(card(), locale: en) == ["60 min", "9 sets", "3,201 kg"])
    }

    @Test func aRunWithNoSetsShowsDistanceAndMinutesOnly() {
        let run = card(seconds: 1800, distance: 5200, sets: 0, volume: 0, prs: 0)
        #expect(WorkoutCardFormat.stats(run, locale: en) == ["30 min", "5.2 km"])
    }

    @Test func aWholeKilometreDropsItsDecimal() {
        #expect(WorkoutCardFormat.stats(card(seconds: 0, distance: 5000, sets: 0, volume: 0), locale: en) == ["5 km"])
    }

    @Test func oneSetIsSingular() {
        #expect(WorkoutCardFormat.stats(card(seconds: 0, sets: 1, volume: 0), locale: en) == ["1 set"])
    }

    @Test func zeroPartsAreLeftOutAndAnEmptyCardHasNoStats() {
        #expect(WorkoutCardFormat.stats(card(seconds: 0, sets: 0, volume: 0), locale: en).isEmpty)
        #expect(WorkoutCardFormat.stats(card(seconds: 20, sets: 0, volume: 0, prs: 0), locale: en).isEmpty, "under half a minute rounds to zero")
    }

    @Test func theDistanceUsesTheReadersDecimalMark() {
        let run = card(seconds: 0, distance: 5200, sets: 0, volume: 0)
        #expect(WorkoutCardFormat.stats(run, locale: es) == ["5,2 km"])
    }

    @Test func theBestSetUsesTheReadersDecimalMark() {
        #expect(WorkoutCardFormat.best("22.5 kg × 8", locale: es) == "22,5 kg × 8")
        #expect(WorkoutCardFormat.best("22.5 kg × 8", locale: en) == "22.5 kg × 8")
        #expect(WorkoutCardFormat.best("100 kg × 5", locale: es) == "100 kg × 5")
    }

    @Test func aCardNamesItsTwoBiggestExercises() {
        let sample = card(exercises: [exercise("Bench"), exercise("Press"), exercise("Fly")])
        #expect(WorkoutCardFormat.top(sample).map(\.name) == ["Bench", "Press"])
    }

    @Test func personalRecordsGetAChipEach() {
        let sample = card(exercises: [exercise("Bench", pr: true), exercise("Press"), exercise("Squat", pr: true)])
        #expect(WorkoutCardFormat.recordNames(sample) == ["Bench", "Squat"])
    }

    @Test func recordsBeyondTheNamedExercisesAreCountedNotLost() {
        let sample = card(prs: 3, exercises: [exercise("Bench", pr: true), exercise("Press")])
        #expect(WorkoutCardFormat.unnamedRecords(sample) == 2)
        let allNamed = card(prs: 2, exercises: [exercise("Bench", pr: true), exercise("Press", pr: true)])
        #expect(WorkoutCardFormat.unnamedRecords(allNamed) == 0)
        #expect(WorkoutCardFormat.unnamedRecords(card(prs: 0)) == 0)
    }

    @Test func anExerciseLineDropsZeroVolumeAndMissingBest() {
        #expect(WorkoutCardFormat.detail(exercise("Bench", sets: 4, volume: 1600), locale: en) == "4 sets · 1,600 kg · 60 kg × 6")
        #expect(WorkoutCardFormat.detail(exercise("Pull-up", sets: 1, volume: 0, best: nil), locale: en) == "1 set")
        #expect(WorkoutCardFormat.detail(exercise("Curl", sets: 3, volume: 22.5, best: "7.5 kg × 10"), locale: es) == "3 sets · 23 kg · 7,5 kg × 10")
    }
}
