import Foundation
import Testing
import UserNotifications
@testable import khepri

struct CheckInNotificationFlowTests {
    @Test func aMoodButtonAsksForEnergy() {
        let step = CheckInNotificationFlow.next(action: "CHECKIN_MOOD_4", userInfo: [:], today: "2026-10-27")
        #expect(step == .askEnergy(mood: 4, day: "2026-10-27"))
    }

    @Test func anEnergyButtonFilesWithTheMoodItCarries() {
        let info: [AnyHashable: Any] = [CheckInActions.moodKey: 4, CheckInActions.dayKey: "2026-10-27"]
        let step = CheckInNotificationFlow.next(action: "CHECKIN_ENERGY_2", userInfo: info, today: "2026-10-27")
        #expect(step == .file(mood: 4, energy: 2))
    }

    /// An energy banner left until tomorrow does not file yesterday's mood
    /// as today's, and says so rather than staying silent.
    @Test func anEnergyButtonFromAnotherDayExpires() {
        let info: [AnyHashable: Any] = [CheckInActions.moodKey: 4, CheckInActions.dayKey: "2026-10-26"]
        let step = CheckInNotificationFlow.next(action: "CHECKIN_ENERGY_2", userInfo: info, today: "2026-10-27")
        #expect(step == .expired(mood: 4))
        let content = CheckInNotificationFlow.expiredContent(mood: 4, thread: "nudges")
        #expect(content.userInfo["url"] as? String == CheckInActions.url(mood: 4).absoluteString)
    }

    /// The second banner goes up before the nudge is counted as opened: the
    /// count is a network call, and a background launch may not outlive it.
    @Test func theEnergyBannerIsPostedBeforeTheOpenIsCounted() async {
        let order = Order()
        await CheckInNotificationFlow.askEnergy(
            mood: 4, day: "2026-10-27", thread: "nudges",
            post: { _ in await order.add("post") },
            countOpen: { await order.add("open") }
        )
        #expect(await order.events == ["post", "open"])
    }

    @Test func theConfirmationOpensTheCheckIns() {
        let content = CheckInNotificationFlow.confirmation(.filed(streak: 8, momentTitle: "A full week"), thread: "nudges")
        #expect(content.title == "Checked in · 8 days in a row" && content.body == "A full week")
        #expect(content.userInfo["url"] as? String == "khepri://check-ins")
    }

    actor Order {
        var events: [String] = []
        func add(_ event: String) { events.append(event) }
    }

    @Test func anythingElseIsNotOurs() {
        #expect(CheckInNotificationFlow.next(action: UNNotificationDefaultActionIdentifier, userInfo: [:], today: "2026-10-27") == .ignore)
        #expect(CheckInNotificationFlow.next(action: "CHECKIN_ENERGY_2", userInfo: [:], today: "2026-10-27") == .ignore)
        #expect(CheckInNotificationFlow.next(action: "CHECKIN_MOOD_9", userInfo: [:], today: "2026-10-27") == .ignore)
    }
}

struct CheckInEnergyBannerTests {
    /// The server sends CHECKIN; the energy category is the app's own and
    /// never travels.
    @Test func bothCategoriesFileInTheBackground() {
        #expect(CheckInActions.category.identifier == "CHECKIN")
        #expect(CheckInActions.energyCategory.identifier == "CHECKIN_ENERGY")
        let actions = CheckInActions.category.actions + CheckInActions.energyCategory.actions
        #expect(actions.count == 6)
        #expect(actions.allSatisfy { !$0.options.contains(.foreground) }, "two taps, without opening the app")
    }

    @Test func theEnergyAskCarriesTheMoodAndTheDay() {
        let request = CheckInActions.energyRequest(mood: 3, day: "2026-10-27", thread: "nudges")
        #expect(request.content.categoryIdentifier == "CHECKIN_ENERGY")
        #expect(request.content.userInfo[CheckInActions.moodKey] as? Int == 3)
        #expect(request.content.userInfo[CheckInActions.dayKey] as? String == "2026-10-27")
        #expect(request.content.threadIdentifier == "nudges")
        // A plain tap, the common case, opens today's check-in with the mood.
        #expect(request.content.userInfo["url"] as? String == CheckInActions.url(mood: 3).absoluteString)
    }
}
