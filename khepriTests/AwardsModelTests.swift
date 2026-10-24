import Foundation
import NorthAPI
import Testing

@testable import khepri

/// The awards screen's states, built from the JSON the web app pins in its
/// golden files (awards.golden.json, unseen.golden.json).
struct AwardsModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    private let earned = """
        {"id": "workouts_1", "area": "training", "name": "First Workout", "description": "Finish your first workout.",
         "earnedAt": "2026-10-22T09:00:00Z", "target": 1, "rarity": "<1%"}
        """
    private let locked = """
        {"id": "streak_30", "area": "consistency", "name": "30-Day Streak", "description": "Check in 30 days in a row.",
         "progress": 12, "target": 30}
        """

    private func model(unseen: [String] = []) throws -> AwardsModel {
        let overview = try decode(AwardsOverview.self, #"{"earned": [\#(earned)], "locked": [\#(locked)]}"#)
        let fresh = try decode([Award].self, "[\(unseen.map { _ in earned }.joined(separator: ","))]")
        return AwardsModel(overview, unseen: fresh)
    }

    @Test func earnedAndLockedAreSplit() throws {
        let model = try model()
        #expect(model.earned.map(\.id) == ["workouts_1"] && model.locked.map(\.id) == ["streak_30"])
        #expect(model.total == 2)
        #expect(model.earned.first?.isEarned == true && model.locked.first?.isEarned == false)
    }

    @Test func aLockedBadgeShowsItsProgress() throws {
        let row = try #require(try model().locked.first)
        #expect(row.fraction == 0.4)
        #expect(row.progressText == "12 of 30")
    }

    @Test func anEarnedBadgeHasNoProgress() throws {
        let row = try #require(try model().earned.first)
        #expect(row.fraction == 0 && row.progressText == nil)
    }

    @Test func progressNeverLeavesTheBar() throws {
        let over = try decode(Award.self, #"{"id": "x", "area": "habits", "name": "X", "description": "x", "progress": 50, "target": 30}"#)
        let none = try decode(Award.self, #"{"id": "y", "area": "habits", "name": "Y", "description": "y", "target": 0}"#)
        let overview = AwardsOverview(earned: [], locked: [over, none])
        let rows = AwardsModel(overview).locked
        #expect(rows.first { $0.id == "x" }?.fraction == 1)
        #expect(rows.first { $0.id == "y" }?.fraction == 0)
    }

    @Test func unseenBadgesAreNew() throws {
        #expect(try model(unseen: ["workouts_1"]).earned.first?.isNew == true)
        #expect(try model().earned.first?.isNew == false)
    }

    @Test func earnedComeNewestFirst() throws {
        let older = try decode(Award.self, #"{"id": "a", "area": "habits", "name": "A", "description": "a", "earnedAt": "2026-01-01T00:00:00Z", "target": 1}"#)
        let newer = try decode(Award.self, #"{"id": "b", "area": "habits", "name": "B", "description": "b", "earnedAt": "2026-06-01T00:00:00Z", "target": 1}"#)
        #expect(AwardsModel(AwardsOverview(earned: [older, newer], locked: [])).earned.map(\.id) == ["b", "a"])
    }

    @Test func theUnseenGoldenShapeDecodes() throws {
        let unseen = try decode(Components.Schemas.UnseenAwards.self, #"{"awards": [\#(earned)]}"#)
        #expect(unseen.awards.map(\.id) == ["workouts_1"])
    }
}

struct SharingAwardsTests {
    @Test func awardsAreOptionalLikeXP() {
        var sharing = Sharing(training: true, streaks: true, goals: true)
        #expect(sharing.awards == nil && !sharing.sharesAwards)
        sharing.sharesAwards = true
        #expect(sharing.awards == true)
    }
}

/// The monthly challenge card's inputs, from the awards response.
struct MonthlyChallengeCardTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    private let challenge = """
        {"month": "2026-10", "metric": "workouts", "target": 5, "progress": 3, "met": false,
         "title": "October challenge", "goal": "Log 5 workouts in October", "progressText": "3 of 5 workouts"}
        """

    @Test func theMonthlyChallengeIsCarriedAsSent() throws {
        let overview = try decode(AwardsOverview.self, #"{"earned": [], "locked": [], "monthlyChallenge": \#(challenge)}"#)
        let shown = try #require(AwardsModel(overview).challenge)
        #expect(shown.title == "October challenge" && shown.progressText == "3 of 5 workouts" && !shown.met)
        #expect(MonthlyChallengeCard.fraction(progress: shown.progress, target: shown.target) == 0.6)
    }

    @Test func noChallengeFromAnOlderServerIsNone() throws {
        let overview = try decode(AwardsOverview.self, #"{"earned": [], "locked": []}"#)
        #expect(AwardsModel(overview).challenge == nil)
    }

    @Test func aMetChallengeFillsTheBar() throws {
        let met = try decode(Components.Schemas.MonthlyChallengeView.self, #"{"month": "2026-10", "metric": "checkin_days", "target": 1, "progress": 1, "met": true, "title": "t", "goal": "g", "progressText": "1 of 1"}"#)
        #expect(met.met && MonthlyChallengeCard.fraction(progress: met.progress, target: met.target) == 1)
        #expect(MonthlyChallengeCard.fraction(progress: 4, target: 0) == 1)
    }
}
