import Foundation
import NorthAPI
import NorthKit
import Testing
@testable import khepri

/// Warm-ups, drop sets and reps in reserve, from the set sheet to
/// `POST /lifts/sets`.
@MainActor
struct SetKindTests {
    @Test func aWarmUpIsLoggedButLeavesThePlanWhereItIs() async {
        let lifts = FakeLifts()
        let session = workout(lifts: lifts)
        session.start()

        await session.completeSet(weightKg: 10, reps: 10, kind: .warmup)
        #expect(session.setNumber == 1, "set 1 is still to come")
        #expect(session.completedSets == 0)
        #expect(session.phase == .working, "no rest after a warm-up")
        #expect(session.suggestedKind == .warmup, "the next set starts as the kind of the one before")
        #expect(session.loggedForCurrent.map(\.kind) == [.warmup])

        await session.completeSet(weightKg: 20, reps: 8, kind: .work, rir: 3)
        #expect(session.setNumber == 2)
        #expect(session.suggestedKind == .work)
        #expect(session.volumeKg == 160, "warm-ups are left out of volume, as on the server")

        await session.finishSaving()
        let sent = await lifts.logged
        #expect(sent.map(\.kind) == [.warmup, nil], "a work set leaves kind out")
        #expect(sent.map(\.rir) == [nil, 3], "a skipped RIR is not sent")
    }

    @Test func theRequestCarriesKindAndRIROnlyWhenGiven() {
        let set = WorkoutSession.LoggedSet.fixture(setNumber: 3, kind: .drop, rir: 2)
        let input = set.input(activitySessionID: "s1")
        #expect(input.kind == .drop)
        #expect(input.rir == 2)
        #expect(input.setNumber == 3)
        #expect(input.exerciseSlug == "goblet-squat")
        #expect(input.activitySessionId == "s1")
        #expect(input.performedAt == set.performedAt, "a resent set keeps the time it was done")

        let plain = WorkoutSession.LoggedSet.fixture(setNumber: 1).input(activitySessionID: nil)
        #expect(plain.kind == nil, "older servers reject the field, and work is the default")
        #expect(plain.rir == nil)
    }

    @Test func lastTimesWarmUpsAreNotWhatAWorkSetStartsFrom() async {
        let lifts = FakeLifts(last: ["goblet squat": [
            .fixture(set: 1, kg: 10, reps: 10, kind: .warmup),
            .fixture(set: 1, kg: 24, reps: 8, kind: .work),
            .fixture(set: 2, kg: 26, reps: 8)
        ]])
        let session = workout(lifts: lifts)
        session.start()
        await session.loadingLastTime?.value

        #expect(session.suggestedWeightKg == 24)
        #expect(LiftSet.fixture(set: 1, kg: 1, reps: 1).setKind == .work, "a server without kinds sends work sets")
    }

    @Test func rirChoicesStopAtFivePlus() {
        #expect(RepsInReserve.choices == [0, 1, 2, 3, 4, 5])
        #expect(RepsInReserve.label(5) == "5+")
        #expect(RepsInReserve.label(0) == "0")
    }
}
