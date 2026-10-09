import Foundation
import NorthAPI
import NorthKit
import Testing
@testable import khepri

// MARK: - Builders

/// The fixture workout with every fake behind it.
@MainActor
func workout(clock: TestClock? = nil, lifts: LiftServicing? = nil, snapshots: WorkoutSnapshotStoring? = nil,
             rest: RestNotificationScheduling? = nil) -> WorkoutSession {
    WorkoutSession.fixture(service: FakeActivity(), live: FakeLiveActivity(), clock: clock ?? TestClock(),
                           lifts: lifts, snapshots: snapshots, restNotifications: rest)
}

/// A workout restored from `snapshot`, timed by `clock`.
@MainActor
func restored(_ snapshot: WorkoutSnapshot, service: FakeActivity? = nil, live: FakeLiveActivity? = nil,
              lifts: LiftServicing? = nil, snapshots: WorkoutSnapshotStoring? = nil,
              rest: RestNotificationScheduling? = nil, clock: TestClock) -> WorkoutSession {
    WorkoutSession(restoring: snapshot, service: service ?? FakeActivity(), live: live ?? FakeLiveActivity(),
                   lifts: lifts, snapshots: snapshots, restNotifications: rest, now: { clock.now })
}

// MARK: - Fakes

@MainActor
final class FakeRestNotifications: RestNotificationScheduling {
    enum Call: Equatable {
        case schedule(RestEnd)
        case cancel
    }

    private(set) var calls: [Call] = []

    func schedule(_ rest: RestEnd) { calls.append(.schedule(rest)) }
    func cancel() { calls.append(.cancel) }
}

final class MemorySnapshots: WorkoutSnapshotStoring, @unchecked Sendable {
    private(set) var saved: WorkoutSnapshot?
    private(set) var clears = 0

    func load(now: Date) -> WorkoutSnapshot? { saved }
    func save(_ snapshot: WorkoutSnapshot) { saved = snapshot }
    func clear() {
        saved = nil
        clears += 1
    }
}

/// A path in the temporary directory, removed when the test is done.
final class TemporaryFile {
    let url = URL.temporaryDirectory
        .appending(components: "khepri-tests-\(UUID().uuidString)", "in-progress.json")

    init() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

extension RestEnd {
    /// The fixture's second set of goblet squats.
    static func squatSet2(endsAt: Date) -> RestEnd {
        RestEnd(endsAt: endsAt, exerciseName: "Goblet squat", setNumber: 2, totalSets: 2)
    }
}

extension WorkoutSession {
    /// Waits for every set upload started so far.
    func finishSaving() async {
        for task in saving { await task.value }
    }
}

extension WorkoutSession.LoggedSet {
    static func fixture(setNumber: Int, kind: SetKind = .work, rir: Int? = nil,
                        upload: SetUpload = .pending) -> WorkoutSession.LoggedSet {
        WorkoutSession.LoggedSet(exerciseKey: "goblet-squat", exerciseName: "Goblet squat",
                                 exerciseSlug: "goblet-squat", setNumber: setNumber, weightKg: 20, reps: 8,
                                 kind: kind, rir: rir, performedAt: Date(timeIntervalSince1970: 1_799_999_000),
                                 upload: upload)
    }
}

extension WorkoutSnapshot {
    /// Squat set 1 of 2 done, working on set 2, joined to server session s1
    /// and Live Activity live-9, started 30 seconds before `savedAt`.
    static func fixture(savedAt: Date) -> WorkoutSnapshot {
        WorkoutSnapshot(
            savedAt: savedAt, title: "Monday · Full body", planWeekday: "Monday",
            exercises: [
                DayExercise(name: "Goblet squat", sets: 2, reps: "8", restSeconds: 90, equipment: "dumbbell",
                            hasArt: true, primaryMuscles: [], secondaryMuscles: []),
                DayExercise(name: "Push-up", sets: 1, reps: "AMRAP", restSeconds: 60, equipment: "none",
                            hasArt: true, primaryMuscles: [], secondaryMuscles: [])
            ],
            exerciseIndex: 0, setNumber: 2, completedSets: 1, startedAt: savedAt.addingTimeInterval(-30),
            restEndsAt: nil, isPaused: false, pausedAt: nil, pausedTotal: 0, restRemaining: nil,
            recorded: .fixture(id: "s1", status: .active), liveActivityID: "live-9", notice: nil,
            logged: [], lastTime: [:])
    }
}
