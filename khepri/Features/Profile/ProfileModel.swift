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

    let name: String
    let handle: String
    let followers: Int
    let following: Int
    let level: Components.Schemas.LevelView?
    let workoutCount: Int?
    let workouts: Workouts
    let awards: Awards
    let isSelf: Bool
    let isFollowing: Bool

    var canFollow: Bool { !isSelf }

    init(_ profile: ProfileView) {
        let extra = profile.value2
        name = profile.value1.displayName
        handle = profile.value1.handle
        followers = extra.followers
        following = extra.following
        level = extra.level
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
