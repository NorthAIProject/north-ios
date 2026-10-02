import Foundation
import NorthAPI

typealias XPSummary = Components.Schemas.XPSummary
typealias XPLevel = Components.Schemas.LevelView
typealias XPEarned = Components.Schemas.EarnedView
typealias Leaderboard = Components.Schemas.Leaderboard
typealias LeaderboardEntry = Components.Schemas.LeaderboardEntry

protocol LeaderboardServicing: Sendable {
    /// Your XP this week by kind, lifetime XP and level.
    func summary() async throws -> XPSummary
    /// You and the friends who share this board's metric with you, ranked.
    func board(_ board: LeaderboardBoard) async throws -> Leaderboard
}

struct LeaderboardService: LeaderboardServicing {
    var api: Client = API.shared

    func summary() async throws -> XPSummary {
        try await NorthAPI.call { try await api.getXP().ok.body.json }
    }

    func board(_ board: LeaderboardBoard) async throws -> Leaderboard {
        try await NorthAPI.call {
            try await api.getLeaderboard(query: .init(metric: board.metric, period: board.period)).ok.body.json
        }
    }
}

/// The four boards, in the order the web page offers them.
enum LeaderboardBoard: String, CaseIterable, Identifiable, Sendable {
    case xpWeek, xpAll, streak, workouts

    var id: Self { self }

    /// The board's name, as the web page words it.
    var label: String {
        switch self {
        case .xpWeek: "XP this week"
        case .xpAll: "XP all time"
        case .streak: "Streak"
        case .workouts: "Workouts this week"
        }
    }

    /// Short enough for four segments side by side on a phone.
    var segment: String {
        switch self {
        case .xpWeek: "Week"
        case .xpAll: "All Time"
        case .streak: "Streak"
        case .workouts: "Workouts"
        }
    }

    var metric: Operations.GetLeaderboard.Input.Query.MetricPayload {
        switch self {
        case .xpWeek, .xpAll: .xp
        case .streak: .streak
        case .workouts: .workouts
        }
    }

    /// Only XP has a choice; the server ignores it for the others.
    var period: Operations.GetLeaderboard.Input.Query.PeriodPayload? {
        switch self {
        case .xpWeek: .week
        case .xpAll: .all
        case .streak, .workouts: nil
        }
    }

    /// The "What followers see" switch that puts you on this board.
    var sharing: WritableKeyPath<Sharing, Bool> {
        switch self {
        case .xpWeek, .xpAll: \.sharesXP
        case .streak: \.streaks
        case .workouts: \.training
        }
    }

    /// What the button that turns that switch on says.
    var shareAction: String {
        switch self {
        case .xpWeek, .xpAll: "Share Your XP and Level"
        case .streak: "Share Check-in Streaks"
        case .workouts: "Share Workouts You Finish"
        }
    }
}

extension Sharing {
    /// XP is optional on the wire: a server from before the leaderboard
    /// neither sends nor accepts it. Setting it here is what makes a save
    /// send it, so only do that when the server sent it first.
    var sharesXP: Bool {
        get { xp ?? false }
        set { xp = newValue }
    }

    /// This sharing with the switch for `board` turned on.
    func turningOn(_ board: LeaderboardBoard) -> Sharing {
        var next = self
        next[keyPath: board.sharing] = true
        return next
    }
}

/// The words and numbers the leaderboard shows, kept apart from the view so
/// they can be tested. Wording follows the web page.
enum XPFormat {
    /// How far into the current level, 0...1; nil at the top level.
    static func progress(total: Int, floor: Int, next: Int?) -> Double? {
        guard let next, next > floor else { return nil }
        return min(max(Double(total - floor) / Double(next - floor), 0), 1)
    }

    /// "340 XP · 460 to the next level", or "6200 XP · the top level".
    static func levelCaption(total: Int, next: Int?) -> String {
        guard let next else { return "\(total) XP · the top level" }
        return "\(total) XP · \(max(next - total, 0)) to the next level"
    }

    /// "210 XP", "12 days", "3 workouts", by the board's metric.
    static func value(_ value: Int, metric: Leaderboard.MetricPayload) -> String {
        switch metric {
        case .xp: "\(value) XP"
        case .streak: value == 1 ? "1 day" : "\(value) days"
        case .workouts: value == 1 ? "1 workout" : "\(value) workouts"
        }
    }

    /// What each kind pays for, rules included.
    static func kindLabel(_ kind: XPEarned.KindPayload) -> String {
        switch kind {
        case .workout: "Workouts of 10 min or more (up to 2 a day)"
        case .habitKept: "Habits kept on their days"
        case .streakDay: "Check-in streak days (from day 3)"
        case .milestone: "Milestones reached"
        case .goal: "Goals achieved"
        }
    }

    /// "2 × · 40 XP"
    static func earned(count: Int, points: Int) -> String {
        "\(count) × · \(points) XP"
    }
}
