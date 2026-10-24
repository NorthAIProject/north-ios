import Foundation
import NorthAPI

/// What a profile screen shows, decided from the response alone.
struct ProfileModel: Equatable {
    /// The workouts section: not shared with you, shared but nothing yet, or a list.
    enum Workouts: Equatable {
        case hidden
        case empty
        case list([WorkoutCard])
    }

    /// The awards strip: not shared with you, shared but none yet, or the badges, newest first.
    enum Awards: Equatable {
        case hidden
        case empty
        case list([Award])
    }

    /// Where a profile's "See all" for awards leads.
    enum AwardsLink: Equatable {
        /// Your own profile: the full screen with what is still to earn.
        case mine
        /// Someone else's: the badges their profile response carries.
        case theirs
    }

    let name: String
    let handle: String
    let followers: Int
    let following: Int
    let level: Components.Schemas.LevelView?
    let workoutCount: Int?
    let workouts: Workouts
    let awards: Awards
    let monthlyChallenge: Components.Schemas.MonthlyChallengeView?
    let isSelf: Bool
    let isFollowing: Bool

    /// Nil when there are no badges to see on someone else's profile. Your own
    /// always leads to the full screen, which also lists what is still to earn,
    /// so a new person with nothing yet is not left at a dead end. Not when
    /// awards are hidden, which can only be a server that does not know them.
    var awardsLink: AwardsLink? {
        if isSelf {
            if case .hidden = awards { return nil }
            return .mine
        }
        guard case .list = awards else { return nil }
        return .theirs
    }

    var canFollow: Bool { !isSelf }

    init(_ profile: ProfileView) {
        let extra = profile.value2
        name = profile.value1.displayName
        handle = profile.value1.handle
        followers = extra.followers
        following = extra.following
        level = extra.level
        monthlyChallenge = extra.monthlyChallenge
        workoutCount = extra.workouts
        isSelf = extra.relationship._self
        // Pending counts: the follow was made, whatever the server calls it.
        isFollowing = !extra.relationship.following.isEmpty
        // A server that says nothing about sharing is not trusted to share.
        if extra.shares?.training != true {
            workouts = .hidden
        } else if let recent = extra.recentWorkouts, !recent.isEmpty {
            workouts = .list(recent)
        } else {
            workouts = .empty
        }
        // Same trust rule as workouts. The server leaves `awards` out when there are none.
        if extra.shares?.awards != true {
            awards = .hidden
        } else if let held = extra.awards, !held.isEmpty {
            awards = .list(held.sorted { ($0.earnedAt ?? .distantPast) > ($1.earnedAt ?? .distantPast) })
        } else {
            awards = .empty
        }
    }
}
