import Foundation
import NorthAPI

typealias GoalSummary = Components.Schemas.GoalSummary
typealias GoalDetail = Components.Schemas.GoalDetail
typealias GoalMilestone = Components.Schemas.Milestone
typealias GoalUpdate = Components.Schemas.GoalUpdate
typealias GoalRequest = Components.Schemas.GoalRequest

/// What a goal is made of, as the create and edit form holds it.
struct GoalDraft: Equatable {
    var title = ""
    var motivation = ""
    var success = ""
    var category = "personal"
    var targetDate: Date?

    init() {}

    init(goal: GoalDetail) {
        title = goal.summary.title
        motivation = goal.motivation
        success = goal.success
        category = goal.summary.category
        targetDate = goal.summary.targetDate.flatMap(CalendarDay.date(from:))
    }

    var request: GoalRequest {
        .init(title: title, motivation: motivation, success: success, category: category,
              targetDate: targetDate.map(CalendarDay.string(from:)))
    }
}

/// Dates that are days, not moments: a goal's deadline has no time or zone,
/// so it travels as YYYY-MM-DD and is shown in the device's calendar.
enum CalendarDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}

extension GoalDetail {
    /// allOf generates a pair of values; these read like the one object it is.
    var summary: GoalSummary { value1 }
    var motivation: String { value2.motivation }
    var success: String { value2.success }
    var milestones: [GoalMilestone] { value2.milestones }
    var updates: [GoalUpdate] { value2.updates }
}

protocol GoalsServicing: Sendable {
    func goals() async throws -> Components.Schemas.GoalList
    func goal(_ id: String) async throws -> GoalDetail
    func create(_ draft: GoalDraft) async throws -> GoalDetail
    func update(_ id: String, _ draft: GoalDraft) async throws -> GoalDetail
    func setStatus(_ id: String, _ status: String) async throws -> GoalDetail
    func delete(_ id: String) async throws
    func addNote(_ id: String, note: String, progress: Int?) async throws
    func addMilestone(_ id: String, title: String) async throws
    func setMilestone(_ goalID: String, _ milestoneID: String, completed: Bool) async throws
    /// Renames a milestone or moves its date; nil clears the date.
    func updateMilestone(_ goalID: String, _ milestoneID: String, title: String, targetDate: Date?) async throws
    func deleteMilestone(_ goalID: String, _ milestoneID: String) async throws
}

struct GoalsService: GoalsServicing {
    var api: Client = API.shared

    func goals() async throws -> Components.Schemas.GoalList {
        try await NorthAPI.call { try await api.listGoals().ok.body.json }
    }

    func goal(_ id: String) async throws -> GoalDetail {
        try await NorthAPI.call { try await api.getGoal(path: .init(goalID: id)).ok.body.json }
    }

    func create(_ draft: GoalDraft) async throws -> GoalDetail {
        try await NorthAPI.call { try await api.createGoal(body: .json(draft.request)).created.body.json }
    }

    func update(_ id: String, _ draft: GoalDraft) async throws -> GoalDetail {
        try await NorthAPI.call { try await api.updateGoal(path: .init(goalID: id), body: .json(draft.request)).ok.body.json }
    }

    func setStatus(_ id: String, _ status: String) async throws -> GoalDetail {
        try await NorthAPI.call { try await api.setGoalStatus(path: .init(goalID: id), body: .json(.init(status: status))).ok.body.json }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteGoal(path: .init(goalID: id)).noContent }
    }

    func addNote(_ id: String, note: String, progress: Int?) async throws {
        try await NorthAPI.call {
            _ = try await api.addGoalUpdate(path: .init(goalID: id), body: .json(.init(note: note, progress: progress))).created
        }
    }

    func addMilestone(_ id: String, title: String) async throws {
        try await NorthAPI.call { _ = try await api.addMilestone(path: .init(goalID: id), body: .json(.init(title: title))).created }
    }

    func setMilestone(_ goalID: String, _ milestoneID: String, completed: Bool) async throws {
        try await NorthAPI.call {
            _ = try await api.setMilestoneStatus(path: .init(goalID: goalID, milestoneID: milestoneID),
                                                 body: .json(.init(status: completed ? "completed" : "open"))).ok
        }
    }

    func updateMilestone(_ goalID: String, _ milestoneID: String, title: String, targetDate: Date?) async throws {
        let body = Components.Schemas.MilestoneRequest(title: title, targetDate: targetDate.map(CalendarDay.string(from:)))
        try await NorthAPI.call {
            _ = try await api.updateMilestone(path: .init(goalID: goalID, milestoneID: milestoneID), body: .json(body)).ok
        }
    }

    func deleteMilestone(_ goalID: String, _ milestoneID: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteMilestone(path: .init(goalID: goalID, milestoneID: milestoneID)).noContent }
    }
}
