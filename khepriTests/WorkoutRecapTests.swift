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
            .init(name: "Bench press", sets: 3, volumeKg: 720, e1rmKg: 68, previousVolumeKg: 690, changeE1rmKg: 1.5),
            .init(name: "Row", sets: 3, volumeKg: 740, e1rmKg: 70),
        ]))

        #expect(model.sentence == "40 minutes, 6 sets, 1,460 kg.")
        #expect(model.bars.map(\.exercise) == ["Bench press", "Bench press", "Row"])
        #expect(model.bars.map(\.series) == [.now, .before, .now])
        #expect(model.hasComparison && model.hasVolume)
    }

    @Test func aFirstWorkoutHasNoComparison() {
        let model = WorkoutRecapModel(recap([.init(name: "Push-up", sets: 3, volumeKg: 0, e1rmKg: 0)]))

        #expect(!model.hasComparison)
        #expect(!model.hasVolume, "bodyweight only: no bars worth drawing")
    }
}
