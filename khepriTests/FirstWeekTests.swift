import Foundation
import NorthAPI
import Testing
import UserNotifications
@testable import khepri

struct FirstWeekTests {
    @Test func onlyDaysOneToSevenOfARunningWeekShow() {
        #expect(week(status: "active", day: 1).isUnderWay)
        #expect(week(status: "active", day: 7).isUnderWay)
        // The start date has nothing to do yet.
        #expect(!week(status: "active", day: 0).isUnderWay)
        #expect(!week(status: "active", day: 8).isUnderWay)
        #expect(!week(status: "finished", day: 7).isUnderWay)
        #expect(!week(status: "none", day: 0).isUnderWay)
        // An open string: a status this build has never heard of shows nothing.
        #expect(!week(status: "paused", day: 3).isUnderWay)
    }

    @Test func threeForThreeOnlyOnDayThreeWithEveryDayDone() {
        #expect(week(status: "active", day: 3, done: [true, true, true]).threeForThree)
        #expect(!week(status: "active", day: 3, done: [true, false, true]).threeForThree)
        #expect(!week(status: "active", day: 4, done: [true, true, true, false]).threeForThree)
    }

    // The week loads before anything is shown: the store, not the card,
    // fetches, so an empty card is never what decides whether it loads.
    @MainActor
    @Test func theStoreLoadsTheWeekAndMarksTheDayDone() async {
        let store = FirstWeekStore(service: FakeFirstWeek())
        await store.load()
        #expect(store.week?.isUnderWay == true && store.week?.done == false)
        await store.markDone()
        #expect(store.week?.done == true && store.week?.doneCount == 3 && store.error == nil)
        #expect(store.week?.threeForThree == true)
    }

    @MainActor
    @Test func aFailedDoneKeepsTheWeekAndSaysWhy() async {
        let store = FirstWeekStore(service: FakeFirstWeek(failsDone: true))
        await store.load()
        await store.markDone()
        #expect(store.week?.done == false && store.error != nil && !store.saving)
    }
}

@MainActor
struct FirstWeekActionsTests {
    /// The name must match nudges.CategoryCoachFirstWeek on the server, or the
    /// banner arrives without the button.
    @Test func categoryMatchesTheServer() {
        #expect(FirstWeekActions.category == "COACH_FIRST_WEEK")
        #expect(FirstWeekActions.notificationCategory.identifier == "COACH_FIRST_WEEK")
    }

    /// Done is answered in the background, and not as a coach answer: the
    /// evening note has no coach message to answer.
    @Test func doneIsItsOwnBackgroundAction() {
        let actions = FirstWeekActions.notificationCategory.actions
        #expect(actions.map(\.identifier) == [FirstWeekActions.doneAction])
        #expect(actions.allSatisfy { !$0.options.contains(.foreground) })
        #expect(CoachActions.answer(forAction: FirstWeekActions.doneAction) == nil)
    }
}

private func week(status: String, day: Int, done: [Bool] = []) -> FirstWeek {
    let days = (1...7).map { n in
        Components.Schemas.FirstWeekDay(day: n, date: "2026-10-2\(n)", done: n <= done.count ? done[n - 1] : false)
    }
    return FirstWeek(status: status, day: day, totalDays: 7, done: false, doneCount: done.filter { $0 }.count, days: days)
}

private struct FakeFirstWeek: FirstWeekServicing {
    var failsDone = false

    func current() async throws -> FirstWeek {
        var current = week(status: "active", day: 3, done: [true, true])
        current.action = "Wind down 30 minutes before bed."
        return current
    }

    func markDone() async throws -> FirstWeek {
        if failsDone { throw URLError(.notConnectedToInternet) }
        var current = week(status: "active", day: 3, done: [true, true, true])
        current.done = true
        return current
    }
}
