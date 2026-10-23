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

    // From day 7 until the review is opened the card offers the review; after
    // day 7 there is nothing left to mark done.
    @Test func theReviewIsReadyFromDaySevenWhileTheWeekRuns() {
        #expect(!week(status: "active", day: 6).reviewReady)
        #expect(week(status: "active", day: 7).reviewReady && week(status: "active", day: 7).isUnderWay)
        #expect(week(status: "active", day: 9).reviewReady && week(status: "active", day: 9).isOver)
        #expect(week(status: "active", day: 9).showsCard && !week(status: "active", day: 9).isUnderWay)
        #expect(!week(status: "finished", day: 7).showsCard)
        #expect(!week(status: "active", day: 0).showsCard)
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
struct FirstWeekReviewTests {
    // Opening the review closes the week; a second open (the sheet's task
    // running again) must not send another finish.
    @Test func openingFinishesOnceAndShowsTheReview() async {
        let service = CountingFirstWeek()
        let store = FirstWeekReviewStore(service: service)
        await store.open()
        await store.open()
        #expect(await service.finishes == 1)
        #expect(store.review?.text == "Five of seven nights." && store.review?.daysDone == 5 && store.error == nil)
    }

    // Already finished elsewhere: finish answers 409, the review still shows.
    @Test func aRefusedFinishFallsBackToTheWeeksReview() async {
        let store = FirstWeekReviewStore(service: CountingFirstWeek(refusesFinish: true))
        await store.open()
        #expect(store.review?.daysDone == 5 && store.error == nil)
    }

    // No review anywhere: say so rather than spin.
    @Test func noReviewAnywhereIsAnError() async {
        let store = FirstWeekReviewStore(service: CountingFirstWeek(refusesFinish: true, hasReview: false))
        await store.open()
        #expect(store.review == nil && store.error != nil)
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

private func reviewed(status: String) -> FirstWeek {
    var finished = week(status: status, day: 7, done: [true, true, true, true, false, true, false])
    finished.review = FirstWeekReview(text: "Five of seven nights.", writtenBy: "coach", daysDone: 5, daysByLog: 4,
                                      daysByTap: 1, createdAt: Date(timeIntervalSince1970: 1_793_000_000))
    return finished
}

private actor CountingFirstWeek: FirstWeekServicing {
    let refusesFinish: Bool
    let hasReview: Bool
    private(set) var finishes = 0

    init(refusesFinish: Bool = false, hasReview: Bool = true) {
        self.refusesFinish = refusesFinish
        self.hasReview = hasReview
    }

    func current() async throws -> FirstWeek {
        hasReview ? reviewed(status: "finished") : week(status: "finished", day: 7)
    }

    func markDone() async throws -> FirstWeek { try await current() }

    func finish() async throws -> FirstWeek {
        finishes += 1
        if refusesFinish { throw URLError(.badServerResponse) }
        return reviewed(status: "finished")
    }
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

    func finish() async throws -> FirstWeek {
        reviewed(status: "finished")
    }
}
