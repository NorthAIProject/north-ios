import Foundation
import NorthAPI
import Testing

@testable import khepri

/// The profile states, built from the JSON the web app pins in its golden
/// files (see NorthKit's Contract directory).
struct ProfileScreenModelTests {
    private func profile(_ json: String) throws -> ProfileView {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileView.self, from: Data(json.utf8))
    }

    private let person = #""id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "displayName": "Ana", "handle": "ana_runs", "followers": 12, "following": 9"#
    private let workout = """
        {"sessionId": "11111111-1111-1111-1111-111111111111", "name": "Push day", "activityCode": "strength_training_light",
         "startedAt": "2026-10-20T17:30:00Z", "endedAt": "2026-10-20T18:30:00Z", "durationSeconds": 3600, "sets": 9,
         "volumeKg": 3200.5, "prs": 1, "exercises": [{"name": "Bench press", "sets": 4, "volumeKg": 1600, "best": "100 kg × 5", "pr": true}]}
        """

    private func relationship(following: String = "accepted", isSelf: Bool = false) -> String {
        #""relationship": {"following": "\#(following)", "followsYou": true, "self": \#(isSelf)}"#
    }

    @Test func aSharedProfileListsItsWorkouts() throws {
        let json = """
            {\(person), \(relationship()), "shares": {"training": true, "xp": true},
             "level": {"number": 3, "title": "Regular", "floor": 300, "next": 800}, "workouts": 14, "recentWorkouts": [\(workout)]}
            """
        let model = ProfileModel(try profile(json))
        guard case .list(let cards) = model.workouts else { Issue.record("expected a list, got \(model.workouts)"); return }
        #expect(cards.map(\.name) == ["Push day"])
        #expect(model.workoutCount == 14)
        #expect(model.level?.number == 3 && model.level?.title == "Regular")
        #expect(model.name == "Ana" && model.handle == "ana_runs" && model.followers == 12 && model.following == 9)
        #expect(model.canFollow && model.isFollowing)
    }

    @Test func aPrivateProfileSaysHiddenAndShowsNoNumbers() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false}}"#
        let model = ProfileModel(try profile(json))
        #expect(model.workouts == .hidden)
        #expect(model.workoutCount == nil && model.level == nil)
    }

    @Test func sharedWithNothingYetSaysEmptyNotHidden() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": true, "xp": false}, "workouts": 0}"#
        let model = ProfileModel(try profile(json))
        #expect(model.workouts == .empty)
        #expect(model.workoutCount == 0)
    }

    @Test func yourOwnProfileHasNoFollowButton() throws {
        let json = #"{\#(person), \#(relationship(following: "", isSelf: true)), "shares": {"training": true, "xp": true}, "workouts": 0}"#
        let model = ProfileModel(try profile(json))
        #expect(!model.canFollow && !model.isFollowing)
    }

    @Test func aStrangerCanBeFollowed() throws {
        let json = #"{\#(person), \#(relationship(following: "")), "shares": {"training": false, "xp": false}}"#
        let model = ProfileModel(try profile(json))
        #expect(model.canFollow && !model.isFollowing)
    }

    @Test func aServerThatSendsNoSharesIsTreatedAsHidden() throws {
        let model = ProfileModel(try profile(#"{\#(person), \#(relationship())}"#))
        #expect(model.workouts == .hidden)
    }

    private let badge = """
        {"id": "workouts_1", "area": "training", "name": "First Workout", "description": "Finish your first workout.",
         "earnedAt": "2026-10-20T18:30:00Z", "target": 1}
        """
    private let newerBadge = """
        {"id": "pr_1", "area": "lifts", "name": "First Personal Record", "description": "Set your first personal record.",
         "earnedAt": "2026-10-21T18:30:00Z", "target": 1}
        """

    @Test func sharedAwardsListNewestFirst() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false, "awards": true}, "awards": [\#(badge), \#(newerBadge)]}"#
        guard case .list(let held) = ProfileModel(try profile(json)).awards else { Issue.record("expected a list"); return }
        #expect(held.map(\.id) == ["pr_1", "workouts_1"])
    }

    @Test func awardsSharedWithNoneYetSaysEmptyNotHidden() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false, "awards": true}}"#
        #expect(ProfileModel(try profile(json)).awards == .empty)
    }

    @Test func awardsKeptPrivateAreHidden() throws {
        let off = #"{\#(person), \#(relationship()), "shares": {"training": true, "xp": true, "awards": false}}"#
        #expect(ProfileModel(try profile(off)).awards == .hidden)
    }

    @Test func aServerFromBeforeAwardsIsTreatedAsHidden() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": true, "xp": true}}"#
        #expect(ProfileModel(try profile(json)).awards == .hidden)
        #expect(ProfileModel(try profile(#"{\#(person), \#(relationship())}"#)).awards == .hidden)
    }

    @Test func seeAllGoesToTheFullScreenOnYourOwnProfile() throws {
        let json = #"{\#(person), \#(relationship(following: "", isSelf: true)), "shares": {"training": true, "xp": true, "awards": true}, "awards": [\#(badge)]}"#
        #expect(ProfileModel(try profile(json)).awardsLink == .mine)
    }

    @Test func seeAllListsTheirBadgesOnSomeoneElsesProfile() throws {
        let json = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false, "awards": true}, "awards": [\#(badge)]}"#
        #expect(ProfileModel(try profile(json)).awardsLink == .theirs)
    }

    @Test func seeAllIsHiddenWithoutBadges() throws {
        let none = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false, "awards": true}}"#
        let hidden = #"{\#(person), \#(relationship()), "shares": {"training": false, "xp": false, "awards": false}}"#
        for json in [none, hidden] { #expect(ProfileModel(try profile(json)).awardsLink == nil) }
    }

    @Test func yourOwnProfileOffersSeeAllEvenWithNoBadges() throws {
        let mine = #"{\#(person), \#(relationship(following: "", isSelf: true)), "shares": {"training": true, "xp": true, "awards": true}}"#
        #expect(ProfileModel(try profile(mine)).awardsLink == .mine)
    }
}
