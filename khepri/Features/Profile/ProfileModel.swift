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

    let name: String
    let handle: String
    let followers: Int
    let following: Int
    let level: Components.Schemas.LevelView?
    let workoutCount: Int?
    let workouts: Workouts
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
    }
}
