import Foundation
import NorthAPI
import NorthKit
import Testing
@testable import khepri

@MainActor
struct WorkoutSessionTests {
    @Test func walksSetsThenExercisesRestingAsPrescribed() async {
        let clock = TestClock()
        let live = FakeLiveActivity()
        let session = WorkoutSession.fixture(service: FakeActivity(), live: live, clock: clock)

        session.start()
        #expect(session.phase == .working)
        #expect(live.started?.exerciseName == "Goblet squat")

        await session.completeSet()                        // squat 1 of 2
        #expect(session.setNumber == 2)
        #expect(session.phase == .resting(until: clock.now.addingTimeInterval(90)))
        #expect(live.last?.phase == .resting)

        session.endRest()
        await session.completeSet()                        // squat 2 of 2: on to push-ups
        #expect(session.current?.name == "Push-up")
        #expect(session.setNumber == 1)
        #expect(session.restEndsAt == clock.now.addingTimeInterval(90), "rest after an exercise is that exercise's rest")
    }

    @Test func finishingTheLastSetStopsTheServerSession() async {
        let service = FakeActivity()
        let live = FakeLiveActivity()
        let session = WorkoutSession.fixture(service: service, live: live, clock: TestClock())
        session.start()

        for _ in 0..<session.totalSets {
            session.endRest()
            await session.completeSet()
        }

        #expect(session.phase == .finished)
        #expect(session.completedSets == 3)
        #expect(service.calls == ["start strength_training", "stop s1"])
        #expect(session.recorded?.status == .completed)
        #expect(live.ended)
    }

    @Test func aServerRefusalKeepsTheWorkoutGoingAndSaysWhy() async {
        let service = FakeActivity(startError: .fieldValidation(
            message: "Add your weight in Settings so calories can be estimated.", fields: ["weight": "required"]))
        let session = WorkoutSession.fixture(service: service, live: FakeLiveActivity(), clock: TestClock())

        session.start()
        await session.completeSet()
        #expect(session.setNumber == 2, "the workout does not wait on the server")

        await session.finish()
        #expect(session.recorded == nil)
        #expect(session.notice?.contains("Add your weight") == true)
        #expect(!service.calls.contains { $0.hasPrefix("stop") })
    }

    @Test func joinsASessionAlreadyOpenOnTheAccount() async {
        let service = FakeActivity(startError: .server("A session is already running."), open: .fixture(id: "web", status: .active))
        let session = WorkoutSession.fixture(service: service, live: FakeLiveActivity(), clock: TestClock())

        session.start()
        await session.finish()

        #expect(service.calls.last == "stop web")
        #expect(session.notice?.contains("already running") == true)
    }

    @Test func pausingMidRestKeepsTheRestLeft() async {
        let clock = TestClock()
        let service = FakeActivity()
        let session = WorkoutSession.fixture(service: service, live: FakeLiveActivity(), clock: clock)
        session.start()
        await session.completeSet()                        // 90s rest begins

        clock.advance(30)
        await session.pause()
        clock.advance(600)                                 // a long phone call
        await session.resume()

        #expect(session.restEndsAt == clock.now.addingTimeInterval(60))
        #expect(session.movingTime == 30)
        #expect(service.calls == ["start strength_training", "pause s1", "resume s1"])
    }

    @Test func discardingCancelsOnTheServer() async {
        let service = FakeActivity()
        let live = FakeLiveActivity()
        let session = WorkoutSession.fixture(service: service, live: live, clock: TestClock())
        session.start()

        await session.discard()

        #expect(service.calls.last == "cancel s1")
        #expect(session.recorded == nil)
        #expect(live.dismissedImmediately)
    }
}

// MARK: - Fakes

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@MainActor
final class FakeLiveActivity: WorkoutLiveActivityControlling {
    private(set) var started: WorkoutLiveState?
    private(set) var last: WorkoutLiveState?
    private(set) var ended = false
    private(set) var dismissedImmediately = false

    func start(title: String, startedAt: Date, state: WorkoutLiveState) { started = state; last = state }
    func update(_ state: WorkoutLiveState) { last = state }
    func end(_ state: WorkoutLiveState, dismissImmediately: Bool) {
        ended = true
        dismissedImmediately = dismissImmediately
    }
}

final class FakeActivity: ActivityServicing, @unchecked Sendable {
    private(set) var calls: [String] = []
    private let startError: APIError?
    private let open: ActivitySession?

    init(startError: APIError? = nil, open: ActivitySession? = nil) {
        self.startError = startError
        self.open = open
    }

    func start(_ activityCode: String) async throws -> ActivitySession {
        calls.append("start \(activityCode)")
        if let startError { throw startError }
        return .fixture(id: "s1", status: .active)
    }

    func openSession() async throws -> ActivitySession? { open }

    func pause(_ sessionID: String) async throws -> ActivitySession {
        calls.append("pause \(sessionID)")
        return .fixture(id: sessionID, status: .paused)
    }

    func resume(_ sessionID: String) async throws -> ActivitySession {
        calls.append("resume \(sessionID)")
        return .fixture(id: sessionID, status: .active)
    }

    func stop(_ sessionID: String) async throws -> ActivitySession {
        calls.append("stop \(sessionID)")
        return .fixture(id: sessionID, status: .completed)
    }

    func cancel(_ sessionID: String) async throws {
        calls.append("cancel \(sessionID)")
    }

    func overview() async throws -> Components.Schemas.ActivityOverview {
        .init(active: open, recent: [], kinds: [])
    }

    func log(_ request: Components.Schemas.LogActivityRequest) async throws -> ActivitySession {
        calls.append("log \(request.activityCode) \(request.durationMinutes)")
        return .fixture(id: "logged", status: .completed)
    }
}

extension ActivitySession {
    static func fixture(id: String, status: StatusPayload) -> ActivitySession {
        ActivitySession(id: id, activityCode: "strength_training", activityName: "Strength training (general)",
                        source: "manual", status: status, startedAt: .now, totalPausedSeconds: 0, elapsedSeconds: 0)
    }
}

extension WorkoutSession {
    /// Two sets of squats with 90s rest, then one set of push-ups.
    static func fixture(service: ActivityServicing, live: WorkoutLiveActivityControlling, clock: TestClock) -> WorkoutSession {
        let day = TrainingDay(weekday: "Monday", focus: "Full body", exercises: [
            DayExercise(name: "Goblet squat", sets: 2, reps: "8", restSeconds: 90, equipment: "dumbbell",
                        hasArt: true, primaryMuscles: [], secondaryMuscles: []),
            DayExercise(name: "Push-up", sets: 1, reps: "AMRAP", restSeconds: 60, equipment: "none",
                        hasArt: true, primaryMuscles: [], secondaryMuscles: []),
        ])
        return WorkoutSession(title: "Monday · Full body", day: day, service: service, live: live, now: { clock.now })
    }
}
