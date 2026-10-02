import Foundation
import NorthAPI
import Testing
@testable import khepri

struct XPFormatTests {
    @Test func progressIsHowFarIntoTheLevel() {
        // Regular starts at 300, Committed at 800: 340 is 40 of 500 in.
        #expect(XPFormat.progress(total: 340, floor: 300, next: 800) == 0.08)
        #expect(XPFormat.progress(total: 300, floor: 300, next: 800) == 0)
        #expect(XPFormat.progress(total: 550, floor: 300, next: 800) == 0.5)
    }

    @Test func progressStaysInsideTheBar() {
        #expect(XPFormat.progress(total: 900, floor: 300, next: 800) == 1)
        #expect(XPFormat.progress(total: 100, floor: 300, next: 800) == 0)
    }

    @Test func theTopLevelHasNoProgress() {
        #expect(XPFormat.progress(total: 6200, floor: 6000, next: nil) == nil)
        #expect(XPFormat.progress(total: 10, floor: 0, next: 0) == nil)
    }

    @Test func levelCaption() {
        #expect(XPFormat.levelCaption(total: 340, next: 800) == "340 XP · 460 to the next level")
        #expect(XPFormat.levelCaption(total: 6200, next: nil) == "6200 XP · the top level")
    }

    @Test(arguments: [
        (210, Leaderboard.MetricPayload.xp, "210 XP"),
        (0, .xp, "0 XP"),
        (1, .streak, "1 day"),
        (12, .streak, "12 days"),
        (1, .workouts, "1 workout"),
        (3, .workouts, "3 workouts"),
    ])
    func valueHasTheBoardsUnit(value: Int, metric: Leaderboard.MetricPayload, text: String) {
        #expect(XPFormat.value(value, metric: metric) == text)
    }

    @Test func kindsSayWhatTheyPayFor() {
        #expect(XPFormat.kindLabel(.workout) == "Workouts of 10 min or more (up to 2 a day)")
        #expect(XPFormat.kindLabel(.streakDay) == "Check-in streak days (from day 3)")
        #expect(XPFormat.earned(count: 2, points: 40) == "2 × · 40 XP")
    }
}

struct LeaderboardBoardTests {
    @Test func eachBoardAsksForItsMetricAndPeriod() {
        #expect(LeaderboardBoard.xpWeek.metric == .xp && LeaderboardBoard.xpWeek.period == .week)
        #expect(LeaderboardBoard.xpAll.metric == .xp && LeaderboardBoard.xpAll.period == .all)
        #expect(LeaderboardBoard.streak.metric == .streak && LeaderboardBoard.streak.period == nil)
        #expect(LeaderboardBoard.workouts.metric == .workouts && LeaderboardBoard.workouts.period == nil)
    }

    @Test func turningOnABoardFlipsOnlyItsSwitch() {
        let none = Sharing(training: false, streaks: false, goals: false, xp: false)
        #expect(none.turningOn(.xpWeek) == Sharing(training: false, streaks: false, goals: false, xp: true))
        #expect(none.turningOn(.xpAll).xp == true)
        #expect(none.turningOn(.streak) == Sharing(training: false, streaks: true, goals: false, xp: false))
        #expect(none.turningOn(.workouts) == Sharing(training: true, streaks: false, goals: false, xp: false))
    }

    @Test func aSaveWithoutXPLeavesItOut() throws {
        // A server from before the leaderboard rejects fields it does not know.
        let old = Sharing(training: true, streaks: false, goals: true)
        let body = try #require(String(data: JSONEncoder().encode(old), encoding: .utf8))
        #expect(!body.contains("xp"))
        #expect(!old.sharesXP)
        let on = old.turningOn(.xpWeek)
        #expect(try String(data: JSONEncoder().encode(on), encoding: .utf8)?.contains("\"xp\":true") == true)
    }
}
