import Foundation
import NorthAPI
import Testing
@testable import khepri

struct DecisionRevisitTests {
    @Test func noCalibrationLineBeforeAnyLookBack() {
        #expect(DecisionCalibration(yes: 0, partly: 0, no: 0, revisited: 0).summary == nil)
    }

    @Test func calibrationReadsAsASentence() {
        let line = DecisionCalibration(yes: 4, partly: 2, no: 1, revisited: 7).summary
        #expect(line == "7 looked back on: 4 held, 2 partly, 1 didn't")
    }

    @Test func notYetIsTheEmptyAnswer() {
        #expect(DecisionHeld.notYet.rawValue == "")
        #expect(DecisionHeld(rawValue: "partly") == .partly)
    }
}

struct InboxTests {
    @Test func aGoalSuggestionNamesTheGoal() {
        let suggestion = InboxSuggestion(destination: .init(rawValue: "goal_note")!, goalId: "a", goalTitle: "Run a half marathon", why: "progress")
        #expect(suggestion.home == .goalNote)
        #expect(suggestion.label == "A note on Run a half marathon")
    }

    @Test func aKnowledgeSuggestionCarriesItsTitle() {
        let suggestion = InboxSuggestion(destination: .init(rawValue: "knowledge")!, title: "Zone 2", why: "to keep")
        #expect(suggestion.label == "Knowledge: Zone 2")
    }
}

struct LighterDayTests {
    @Test func theWhyLineNamesBothReadings() {
        let day = LighterDay(offered: true, readiness: .init(low: true, hrv: 38, hrvBaseline: 52, restingHeartRate: 61, restingHeartRateBaseline: 56))
        #expect(day.why == "HRV 38 ms (-27%), resting heart rate 61 bpm (+9%) against your two-week average.")
    }

    @Test func noReadingsNoLine() {
        #expect(LighterDay(offered: false, readiness: .init(low: false)).why == nil)
    }

    @Test func theServersReasonWins() {
        let reason = "Heart rate variability is below your usual: 38ms on Wed 7 Oct, usually 51ms–53ms."
        let day = LighterDay(offered: true, readiness: .init(low: true, hrv: 38, hrvBaseline: 52, reason: reason))
        #expect(day.why == reason)
    }

    // The offer loads before anything is shown: the store, not the card,
    // fetches, so an empty card is never what decides whether it loads.
    @MainActor
    @Test func theStoreLoadsTheOfferAndRecordsTheAnswer() async {
        let store = LighterDayStore(service: FakeLighter())
        await store.load()
        #expect(store.day?.offered == true)
        await store.choose(lighter: true)
        #expect(store.day?.tookItLighter == true && store.day?.offered == false && store.error == nil)
    }
}

private struct FakeLighter: LighterDayServicing {
    func today() async throws -> LighterDay {
        LighterDay(offered: true, readiness: .init(low: true), session: "Lower body")
    }

    func choose(lighter: Bool) async throws -> LighterDay {
        LighterDay(offered: false, readiness: .init(low: true), session: "Lower body", choice: lighter ? .lighter : .keep)
    }
}
