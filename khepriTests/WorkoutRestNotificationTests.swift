import Foundation
import NorthAPI
import NorthKit
import Testing
import UserNotifications
@testable import khepri

/// "Rest over" kept in step with the rest: scheduled when it starts, moved
/// by +15s and resume, taken back by Skip, pause, finish and discard.
@MainActor
struct WorkoutRestNotificationTests {
    @Test func restingSchedulesTheEndAndEveryChangeMovesOrCancelsIt() async {
        let clock = TestClock()
        let rest = FakeRestNotifications()
        let session = workout(clock: clock, rest: rest)
        session.start()
        #expect(rest.calls.isEmpty, "nothing to say before the first rest")

        await session.completeSet()                        // 90s rest before squat set 2
        let end = clock.now.addingTimeInterval(90)
        #expect(rest.calls.last == .schedule(.squatSet2(endsAt: end)))

        session.extendRest(by: 15)
        #expect(rest.calls.last == .schedule(.squatSet2(endsAt: end.addingTimeInterval(15))))

        clock.advance(30)
        await session.pause()
        #expect(rest.calls.last == .cancel, "a paused rest does not run out")

        clock.advance(300)
        await session.resume()
        #expect(rest.calls.last == .schedule(.squatSet2(endsAt: clock.now.addingTimeInterval(75))),
                "rescheduled for the rest that was left")

        session.endRest()
        #expect(rest.calls.last == .cancel, "skipping the rest takes the notification back")
    }

    @Test func finishingOrDiscardingTakesTheNotificationBack() async {
        let finishing = FakeRestNotifications()
        let finished = workout(rest: finishing)
        finished.start()
        await finished.completeSet()
        await finished.finish()
        #expect(finishing.calls.last == .cancel)

        let discarding = FakeRestNotifications()
        let discarded = workout(rest: discarding)
        discarded.start()
        await discarded.completeSet()
        await discarded.discard()
        #expect(discarding.calls.last == .cancel)
    }

    @Test func theNotificationSaysWhatComesNextUnderOneIdentifier() {
        let rest = RestEnd(endsAt: .now.addingTimeInterval(60), exerciseName: "Goblet squat",
                           setNumber: 2, totalSets: 3)
        let request = RestNotifications.request(for: rest, firingIn: 60)

        #expect(request.identifier == RestNotifications.identifier)
        #expect(request.content.title == "Rest over")
        #expect(request.content.body.contains("Goblet squat"))
        #expect(request.content.body.contains("2 of 3"))
        #expect(request.content.interruptionLevel == .active, "no time-sensitive entitlement")
        #expect((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval == 60)
        #expect(!RestNotifications.allowsAlerts(.notDetermined), "never asks for permission mid-workout")
        #expect(!RestNotifications.allowsAlerts(.denied))
        #expect(RestNotifications.allowsAlerts(.authorized))
    }
}
