import Foundation
import NorthAPI
import Testing
@testable import khepri

struct CheckInStreakTests {
    @Test func aStateThisBuildDoesNotKnowReadsAsNone() {
        #expect(CheckInDayState("checked") == .checked)
        #expect(CheckInDayState("rest") == .rest)
        #expect(CheckInDayState("holiday") == .none, "a state added after this build still draws")
    }

    @Test func theHeadlineSaysRestDaysPlainly() {
        #expect(CheckInStreak(days: 1).headline == "1 day in a row")
        #expect(CheckInStreak(days: 12, best: 12, restsUsed: 1).headline == "12 days in a row · 1 rest day")
        #expect(CheckInStreak(days: 15, best: 15, restsUsed: 2).headline == "15 days in a row · 2 rest days")
    }

    @Test func aNewRunNamesTheBestOneNotTheGap() {
        #expect(CheckInStreak(days: 0, best: 23).headline == "New run starts today · best 23")
        #expect(CheckInStreak(days: 1, best: 23).headline == "Day one of a new run · best 23")
        #expect(CheckInStreak(days: 0, best: 0).headline.isEmpty, "nothing before the first check-in")
    }

    @Test func restDaysInHand() {
        #expect(CheckInStreak(days: 7, restsHeld: 0).restsLabel == nil)
        #expect(CheckInStreak(days: 7, restsHeld: 1).restsLabel == "1 rest day in hand")
        #expect(CheckInStreak(days: 14, restsHeld: 2).restsLabel == "2 rest days in hand")
    }

    @Test func theListCarriesTheWholeRun() {
        let list = CheckInList(
            recent: [], streak: 6, bestStreak: 23, restDaysHeld: 1, restDaysUsed: 1, perfectWeek: true,
            week: [.init(date: "2026-09-21", state: "checked"), .init(date: "2026-09-22", state: "rest")]
        )
        let streak = CheckInStreak(list)
        #expect(streak.days == 6 && streak.best == 23 && streak.restsHeld == 1 && streak.restsUsed == 1)
        #expect(streak.perfectWeek && streak.week == [.checked, .rest])
    }
}

struct CheckInCelebrationTests {
    private func saved(created: Bool, moment: String? = nil) -> SavedCheckIn {
        SavedCheckIn(
            value1: CheckIn(id: "c1", localDate: "2026-10-27", mood: 4, energy: 3, wins: "", challenges: "", notes: "",
                            updatedAt: .now, createdAt: .now, source: "ios", tags: []),
            value2: .init(created: created, streak: 7, restDaysHeld: 1, perfectWeek: false,
                          moment: moment.map { .init(kind: $0, title: "A full week", body: "Seven in a row.") })
        )
    }

    @Test func onlyTheSaveThatCreatedTodayCelebrates() {
        #expect(CheckInCelebration(saved: saved(created: false, moment: "streak")) == nil, "an edit is not a moment")
        let celebration = CheckInCelebration(saved: saved(created: true))
        #expect(celebration != nil && celebration?.moment == nil, "a plain first save still gets the haptic")
        #expect(CheckInCelebration(saved: saved(created: true, moment: "streak"))?.moment?.title == "A full week")
    }

    @Test func everyMomentHasASymbolEvenOneThisBuildDoesNotKnow() {
        #expect(CheckInCelebration.symbol(for: "streak") == "flame.fill")
        #expect(CheckInCelebration.symbol(for: "perfect_week") == "star.fill")
        #expect(CheckInCelebration.symbol(for: "rest_day_earned") == "bed.double.fill")
        #expect(CheckInCelebration.symbol(for: "comeback") == "sunrise.fill")
        #expect(CheckInCelebration.symbol(for: "eclipse") == "sparkles")
    }
}

struct CheckInReplyNoteTests {
    @Test func aPatternIsLabelledAndAnythingElseIsADailyNote() {
        #expect(CheckInReplyNote(CheckInReply(kind: "pattern", text: "Sleep drives it."))?.isPattern == true)
        #expect(CheckInReplyNote(CheckInReply(kind: "daily", text: "Good walk."))?.isPattern == false)
        #expect(CheckInReplyNote(CheckInReply(kind: "haiku", text: "Good walk."))?.isPattern == false)
    }

    @Test func noNoteShowsNothing() {
        #expect(CheckInReplyNote(nil) == nil)
        #expect(CheckInReplyNote(CheckInReply(kind: "daily", text: "   ")) == nil)
    }
}
