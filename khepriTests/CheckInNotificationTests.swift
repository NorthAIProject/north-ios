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
    /// as today's.
    @Test func anEnergyButtonFromAnotherDayIsIgnored() {
        let info: [AnyHashable: Any] = [CheckInActions.moodKey: 4, CheckInActions.dayKey: "2026-10-26"]
        #expect(CheckInNotificationFlow.next(action: "CHECKIN_ENERGY_2", userInfo: info, today: "2026-10-27") == .ignore)
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
    }
}
