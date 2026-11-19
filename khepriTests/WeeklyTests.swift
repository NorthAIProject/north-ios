import Foundation
import NorthAPI
import Testing
@testable import khepri

struct WeeklyTests {
    private func review(current: WeeklyFocus? = nil) -> WeeklyReview {
        WeeklyReview(
            reviewing: "2026-09-28",
            planning: "2026-10-05",
            current: current,
            goals: [
                .init(id: "a", title: "Run a half marathon", category: "fitness", priority: 1),
                .init(id: "b", title: "Ship the deck", category: "work", priority: 0),
            ]
        )
    }

    @Test func aFreshReviewStartsFromTheGoalsInTheirOrder() {
        let draft = WeeklyDraft(review: review())
        #expect(draft.goalOrder == ["a", "b"])
        #expect(draft.volume == .hold)
        #expect(draft.submittedPriorities.isEmpty)
    }

    @Test func doingItAgainStartsFromTheLastAnswer() {
        let focus = WeeklyFocus(weekStart: "2026-10-05", priorities: ["Three runs"], volume: .deload, reviewedAt: Date())
        let draft = WeeklyDraft(review: review(current: focus))
        #expect(draft.priorities.first == "Three runs")
        #expect(draft.volume == .deload)
    }

    /// The forecast may suggest a lighter week. It is shown with its reason
    /// and never chosen: the draft still starts on Hold.
    @Test func aSuggestedLighterWeekIsShownNotChosen() {
        var suggested = review()
        suggested.suggestedVolume = "deload"
        suggested.suggestedReason = "Two lifts have stalled."
        #expect(WeeklySuggestion(suggested)?.reason == "Two lifts have stalled.")
        #expect(WeeklyDraft(review: suggested).volume == .hold)
    }

    @Test func nothingIsSuggestedWithoutAReasonOrForAnotherVolume() {
        #expect(WeeklySuggestion(review()) == nil)
        var bare = review()
        bare.suggestedVolume = "deload"
        #expect(WeeklySuggestion(bare) == nil)
        // A volume a later server might suggest is not this build's to show.
        var other = review()
        other.suggestedVolume = "build"
        other.suggestedReason = "You are fresh."
        #expect(WeeklySuggestion(other) == nil)
    }

    @Test func blankPrioritiesDropOut() {
        var draft = WeeklyDraft()
        draft.priorities = ["  Sleep by 23:00 ", "", "Finish the deck"]
        #expect(draft.submittedPriorities == ["Sleep by 23:00", "Finish the deck"])
    }
}

struct WeekVolumeTests {
    private func exercise(sets: Int, thisWeek: Int?) -> DayExercise {
        DayExercise(name: "Goblet squat", sets: sets, thisWeekSets: thisWeek, reps: "8", restSeconds: 90, equipment: "dumbbell",
                    hasArt: false, primaryMuscles: [], secondaryMuscles: [])
    }

    @Test func aDeloadWeekTrainsFewerSets() {
        #expect(exercise(sets: 5, thisWeek: 3).forThisWeek.sets == 3)
    }

    @Test func anOlderServerMeansThePlanAsWritten() {
        #expect(exercise(sets: 4, thisWeek: nil).forThisWeek.sets == 4)
    }
}
