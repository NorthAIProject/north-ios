import Foundation
import NorthAPI
import NorthKit
import Testing
@testable import khepri

/// The workout written down after every change, and a killed run picked up
/// from it: rest by the clock, the Live Activity taken over, unanswered sets
/// sent again.
@MainActor
struct WorkoutSnapshotTests {
    @Test func everyChangeIsWrittenDownAndTheEndClearsIt() async {
        let clock = TestClock()
        let store = MemorySnapshots()
        let session = workout(clock: clock, lifts: FakeLifts(), snapshots: store)
        session.start()
        #expect(store.saved?.startedAt == clock.now)
        #expect(store.saved?.liveActivityID == "live-1")

        await session.completeSet(weightKg: 20, reps: 8, kind: .work, rir: 2)
        await session.loadingLastTime?.value
        #expect(store.saved?.setNumber == 2)
        #expect(store.saved?.restEndsAt == clock.now.addingTimeInterval(90))
        #expect(store.saved?.logged.map(\.rir) == [2])

        await session.pause()
        #expect(store.saved?.isPaused == true)
        #expect(store.saved?.restRemaining == 90)
        #expect(store.saved?.recorded?.id == "s1", "the server session to rejoin")

        await session.finish()
        #expect(store.saved == nil, "a finished workout has nothing to resume")
        #expect(store.clears >= 1)
    }

    @Test func discardingClearsTheSnapshot() async {
        let store = MemorySnapshots()
        let session = workout(snapshots: store)
        session.start()
        await session.discard()
        #expect(store.saved == nil)
    }

    @Test func theFileRoundTripsWithEverySetAndItsServerID() async throws {
        let clock = TestClock()
        let memory = MemorySnapshots()
        let lifts = FakeLifts(last: ["goblet squat": [.fixture(set: 1, kg: 20, reps: 8)]])
        let session = workout(clock: clock, lifts: lifts, snapshots: memory)
        session.start()
        await session.loadingLastTime?.value
        await session.completeSet(weightKg: 15, reps: 10, kind: .warmup)
        await session.completeSet(weightKg: 22.5, reps: 8, kind: .work, rir: 1)
        await session.finishSaving()
        let snapshot = try #require(memory.saved)
        #expect(snapshot.logged.allSatisfy { $0.serverID != nil }, "each set with the id the server gave it")

        let file = TemporaryFile()
        let store = WorkoutSnapshotStore(url: file.url)
        store.save(snapshot)
        let read = try #require(store.load(now: clock.now))

        #expect(read == snapshot)
        #expect(read.logged.map(\.kind) == [.warmup, .work])
        #expect(read.exercises.map(\.name) == ["Goblet squat", "Push-up"])
        #expect(read.lastTime["goblet squat"]?.count == 1)
    }

    @Test func aCorruptOrStaleSnapshotIsIgnoredAndDeleted() throws {
        let file = TemporaryFile()
        let store = WorkoutSnapshotStore(url: file.url)

        try Data("{ not json".utf8).write(to: file.url)
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))

        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(.fixture(savedAt: saved))
        #expect(store.load(now: saved.addingTimeInterval(11 * 3600)) != nil)
        #expect(store.load(now: saved.addingTimeInterval(13 * 3600)) == nil, "half a day untouched is abandoned")
        #expect(!FileManager.default.fileExists(atPath: file.url.path()))

        var future = WorkoutSnapshot.fixture(savedAt: saved)
        future.version = WorkoutSnapshot.currentVersion + 1
        store.save(future)
        #expect(store.load(now: saved) == nil, "another version's shape is not guessed at")

        #expect(WorkoutSnapshotStore(url: file.url.appending(path: "missing.json")).load() == nil)
    }

    // MARK: - Restoring

    @Test func aRestThatRanOutWhileTheAppWasGoneIsOver() async {
        let clock = TestClock()
        let rest = FakeRestNotifications()
        let live = FakeLiveActivity()
        var snapshot = WorkoutSnapshot.fixture(savedAt: clock.now)
        snapshot.restEndsAt = clock.now.addingTimeInterval(60)
        clock.advance(600)

        let session = restored(snapshot, live: live, rest: rest, clock: clock)
        session.start()

        #expect(session.phase == .working)
        #expect(session.setNumber == 2)
        #expect(session.completedSets == 1)
        #expect(rest.calls == [.cancel])
        #expect(live.reattachedTo == "live-9", "the activity on the Lock Screen is taken over")
        #expect(live.started == nil, "not started again")
        #expect(live.last?.phase == .working)
    }

    @Test func aRestStillRunningCarriesOnFromTheClock() async {
        let clock = TestClock()
        let rest = FakeRestNotifications()
        var snapshot = WorkoutSnapshot.fixture(savedAt: clock.now)
        let end = clock.now.addingTimeInterval(90)
        snapshot.restEndsAt = end
        clock.advance(30)

        let session = restored(snapshot, rest: rest, clock: clock)
        session.start()

        #expect(session.restEndsAt == end)
        #expect(rest.calls == [.schedule(.squatSet2(endsAt: end))])
        #expect(session.movingTime == 30 + 30, "the workout kept time while the app was gone")
    }

    @Test func aPausedWorkoutComesBackPaused() async {
        let clock = TestClock()
        var snapshot = WorkoutSnapshot.fixture(savedAt: clock.now)
        snapshot.isPaused = true
        snapshot.pausedAt = clock.now
        snapshot.restEndsAt = clock.now.addingTimeInterval(10)
        snapshot.restRemaining = 40
        clock.advance(120)

        let service = FakeActivity()
        let session = restored(snapshot, service: service, clock: clock)
        session.start()
        #expect(session.isPaused)
        #expect(session.movingTime == 30, "paused time is not moving time")

        await session.resume()
        #expect(session.restEndsAt == clock.now.addingTimeInterval(40))
        #expect(service.calls == ["resume s1"])
    }

    @Test func setsTheServerNeverAnsweredForAreSentAgain() async {
        let clock = TestClock()
        var snapshot = WorkoutSnapshot.fixture(savedAt: clock.now)
        snapshot.logged = [
            .fixture(setNumber: 1, upload: .saved(id: "kept")),
            .fixture(setNumber: 2, kind: .drop, rir: 0, upload: .pending)
        ]
        let lifts = FakeLifts()
        let store = MemorySnapshots()
        let session = restored(snapshot, lifts: lifts, snapshots: store, clock: clock)
        session.start()
        await session.finishSaving()

        let sent = await lifts.logged
        #expect(sent.map(\.setNumber) == [2], "only the pending one")
        #expect(sent.first?.kind == .drop)
        #expect(sent.first?.rir == 0)
        #expect(sent.first?.activitySessionId == "s1")
        #expect(session.logged.map(\.serverID) == ["kept", "set-1"])
        #expect(store.saved?.logged.map(\.serverID) == ["kept", "set-1"])

        await session.discard()
        #expect(await lifts.deleted == ["kept", "set-1"], "a discard takes back sets from before the kill too")
    }

    @Test func aServerSessionThatNeverAnsweredIsRejoinedNotRestarted() async {
        let clock = TestClock()
        var snapshot = WorkoutSnapshot.fixture(savedAt: clock.now)
        snapshot.recorded = nil
        let service = FakeActivity(open: .fixture(id: "web", status: .active))

        let session = restored(snapshot, service: service, clock: clock)
        session.start()
        await session.finish()

        #expect(service.calls == ["stop web"], "joined the open session; never started a second one")
    }
}
