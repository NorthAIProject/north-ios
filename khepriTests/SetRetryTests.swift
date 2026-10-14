import Foundation
import NorthAPI
import NorthKit
import Testing
@testable import khepri

/// A set the server did not take is sent again, with the same client id, so
/// a lost answer never logs it twice.
@MainActor
struct SetRetryTests {
    /// Answers each `log` with the next scripted error, then succeeds.
    actor ScriptedLifts: LiftServicing {
        private var failures: [any Error]
        private(set) var sent: [Components.Schemas.LiftSetInput] = []

        init(failing failures: [any Error]) { self.failures = failures }

        func log(_ input: Components.Schemas.LiftSetInput) async throws -> LiftSet {
            sent.append(input)
            if !failures.isEmpty { throw failures.removeFirst() }
            return .fixture(id: "set-\(sent.count)", set: input.setNumber, kg: input.weightKg, reps: input.reps)
        }
        func last(_ keys: [String]) async throws -> [String: [LiftSet]] { [:] }
        func delete(_ id: String) async throws {}
        func stats(range: String) async throws -> LiftStats {
            LiftStats(range: range, workouts: 0, sets: 0, reps: 0, volumeKg: 0, priorVolumeKg: 0,
                      exercises: [], records: [], weekly: [], muscles: [])
        }
    }

    private func workout(_ lifts: LiftServicing) -> WorkoutSession {
        let day = TrainingDay(weekday: "Monday", focus: "Legs", exercises: [
            DayExercise(name: "Goblet squat", sets: 3, reps: "8", restSeconds: 0, equipment: "dumbbell",
                        hasArt: true, primaryMuscles: [], secondaryMuscles: []),
        ], completedThisWeek: false, isNext: true)
        return WorkoutSession(title: "Legs", day: day, service: FakeActivity(), live: FakeLiveActivity(),
                              lifts: lifts, sleep: { _ in })
    }

    /// Waits, up to a couple of seconds, until `done` holds: sends and
    /// retries run on their own tasks.
    private func waitUntil(_ done: @MainActor () async -> Bool) async {
        for _ in 0..<400 {
            if await done() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Lets every send started so far finish.
    private func settle(_ session: WorkoutSession) async {
        for task in session.saving { await task.value }
    }

    @Test func aSetLostToTheConnectionIsSentAgainWithTheSameClientID() async {
        let lifts = ScriptedLifts(failing: [APIError.network("The network connection was lost.", code: .networkConnectionLost)])
        let session = workout(lifts)
        session.start()

        await session.completeSet(weightKg: 20, reps: 8)
        await waitUntil { session.logged.first?.upload == .saved(id: "set-2") }

        let sent = await lifts.sent
        #expect(sent.count == 2, "the first try failed and the backoff sent it again")
        #expect(Set(sent.map(\.clientId)).count == 1 && sent[0].clientId != nil)
        #expect(sent[0].clientId == session.logged[0].id.uuidString)
        #expect(session.logged[0].upload == .saved(id: "set-2"))
        #expect(session.unsavedSets == 0)
    }

    @Test func aSetTheServerRefusedIsNotRetriedByItself() async {
        let lifts = ScriptedLifts(failing: [APIError.fieldValidation(message: "Reps must be positive.", fields: [:])])
        let session = workout(lifts)
        session.start()

        await session.completeSet(weightKg: 20, reps: 8)
        await settle(session)

        #expect(await lifts.sent.count == 1)
        #expect(session.logged[0].upload == .failed)

        // Coming back to the app still tries it once more.
        session.retryFailedSets()
        await settle(session)
        #expect(await lifts.sent.count == 2)
        #expect(session.logged[0].upload == .saved(id: "set-2"))
    }

    @Test func finishingTheWorkoutSendsFailedSetsOnceMore() async {
        let lifts = ScriptedLifts(failing: [APIError.unauthorized(nil)])
        let session = workout(lifts)
        session.start()
        await session.completeSet(weightKg: 20, reps: 8)
        await settle(session)
        #expect(session.logged[0].upload == .failed)

        await session.finish()
        #expect(await lifts.sent.count == 2)
        #expect(session.logged.isEmpty || session.logged[0].upload == .saved(id: "set-2"))
    }

    @Test func whichFailuresAreWorthRetrying() {
        #expect(WorkoutSession.isWorthRetrying(APIError.network("lost", code: .networkConnectionLost)))
        #expect(WorkoutSession.isWorthRetrying(APIError.server("Something went wrong.")))
        #expect(WorkoutSession.isWorthRetrying(APIError.invalidStatus(503)))
        #expect(WorkoutSession.isWorthRetrying(APIError.invalidStatus(429)))
        #expect(!WorkoutSession.isWorthRetrying(APIError.invalidStatus(400)))
        #expect(!WorkoutSession.isWorthRetrying(APIError.fieldValidation(message: "no", fields: [:])))
        #expect(!WorkoutSession.isWorthRetrying(APIError.notFound(nil)))
        #expect(WorkoutSession.isWorthRetrying(URLError(.timedOut)))
    }
}
