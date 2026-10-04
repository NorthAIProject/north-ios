import Foundation
import NorthAPI
import Testing
@testable import khepri

/// The finish screen's chart reads last time's bars only when the server had a
/// last time, so a first workout never shows an empty comparison.
struct WorkoutRecapTests {
    private func recap(_ exercises: [Components.Schemas.LiftRecapExercise]) -> LiftRecap {
        LiftRecap(sessionId: "s1", startedAt: Date(), planWeekday: "Monday", focus: "Push",
                  sentence: "40 minutes, 6 sets, 1,460 kg.", durationSeconds: 2400, setsDone: 6,
                  setsPrescribed: 6, volumeKg: 1460, calories: 250, exercises: exercises)
    }

    @Test func barsPairThisSessionWithLastTimeWhenThereWasOne() {
        let model = WorkoutRecapModel(recap([
            .init(name: "Bench press", sets: 3, volumeKg: 720, best: "60 kg × 8", e1rmKg: 68,
                  previousVolumeKg: 690, changeE1rmKg: 1.5),
            .init(name: "Row", sets: 3, volumeKg: 740, e1rmKg: 70),
            .init(name: "Squat", sets: 3, volumeKg: 400, e1rmKg: 100, previousVolumeKg: 900, changeE1rmKg: -2)
        ]))

        #expect(model.sentence == "40 minutes, 6 sets, 1,460 kg.")
        // The taller bar is painted first, so the shorter one covers the overlap.
        #expect(model.bars.map(\.exercise) == ["Bench press", "Bench press", "Row", "Squat", "Squat"])
        #expect(model.bars.map(\.series) == [.now, .before, .now, .before, .now])
        #expect(model.hasComparison && model.hasVolume)

        let bench = model.exercises[0]
        #expect(bench.bestWeightKg == 60 && bench.bestReps == 8)
        #expect(bench.e1rmKg == 68 && bench.changeKg == 1.5)
        #expect(model.exercises[1].changeKg == nil)
        #expect(model.exercises[1].previousVolumeKg == nil)
    }

    @Test func axisLabelsStayInsideTheirColumn() {
        let long = "Seated Leg Curl"
        #expect(WorkoutRecapModel.axisLabel(long, among: 1) == long)
        let cramped = WorkoutRecapModel.axisLabel(long, among: 7)
        #expect(cramped.count <= 4)
        #expect(cramped.hasSuffix("…"))
        #expect(!cramped.contains("Curl"))
    }

    @Test func aFirstWorkoutHasNoComparison() {
        let model = WorkoutRecapModel(recap([.init(name: "Push-up", sets: 3, volumeKg: 0, e1rmKg: 0)]))

        #expect(!model.hasComparison)
        #expect(!model.hasVolume, "bodyweight only: no bars worth drawing")
    }
}
