import Foundation
import NorthAPI

typealias WeeklyReview = Components.Schemas.WeeklyReview
typealias WeeklyFocus = Components.Schemas.WeeklyFocus
typealias WeeklyVolume = Components.Schemas.WeeklyFocus.VolumePayload

protocol WeeklyServicing: Sendable {
    func review() async throws -> WeeklyReview
    /// Ends the review: the planned week's priorities and training volume,
    /// and the active goals in the order given.
    func setFocus(priorities: [String], goalOrder: [String], volume: WeeklyVolume) async throws -> WeeklyFocus
}

struct WeeklyService: WeeklyServicing {
    var api: Client = API.shared

    func review() async throws -> WeeklyReview {
        try await NorthAPI.call { try await api.getWeeklyReview().ok.body.json }
    }

    func setFocus(priorities: [String], goalOrder: [String], volume: WeeklyVolume) async throws -> WeeklyFocus {
        let body = Operations.SetWeeklyFocus.Input.Body.JsonPayload(
            priorities: priorities,
            goalOrder: goalOrder,
            volume: .init(rawValue: volume.rawValue) ?? .hold
        )
        return try await NorthAPI.call { try await api.setWeeklyFocus(body: .json(body)).ok.body.json }
    }
}

/// What the person is choosing in the review, kept apart from the view so the
/// rules are testable: blank priorities drop out, at most three survive.
struct WeeklyDraft: Equatable {
    static let maxPriorities = 3

    var priorities: [String] = Array(repeating: "", count: maxPriorities)
    var goalOrder: [String] = []
    var volume: WeeklyVolume = .hold

    init() {}

    /// Starts from a focus already set for the planned week, or from the
    /// goals in their current order.
    init(review: WeeklyReview) {
        if let current = review.current {
            for (index, priority) in current.priorities.prefix(Self.maxPriorities).enumerated() {
                priorities[index] = priority
            }
            volume = current.volume
        }
        goalOrder = review.goals.map(\.id)
    }

    var submittedPriorities: [String] {
        priorities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxPriorities)
            .map { $0 }
    }
}

extension WeeklyVolume {
    var title: String {
        switch self {
        case .hold: "Hold"
        case .build: "Build"
        case .deload: "Deload"
        }
    }

    var explanation: String {
        switch self {
        case .hold: "Train the plan as written."
        case .build: "One extra set on each day's first two exercises."
        case .deload: "About 60% of the sets, to recover."
        }
    }
}
