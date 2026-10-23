import Foundation
import NorthAPI

typealias Award = Components.Schemas.AwardView
typealias AwardsOverview = Components.Schemas.Awards

protocol AwardsServicing: Sendable {
    /// Your badges: those earned, and those still to earn with their progress.
    func awards() async throws -> AwardsOverview
    /// Badges earned that no device has celebrated yet.
    func unseen() async throws -> [Award]
    /// Says a badge was celebrated, so no other device repeats it. Repeating it is fine.
    func markSeen(_ badgeID: String) async throws
}

struct AwardsService: AwardsServicing {
    var api: Client = API.shared

    func awards() async throws -> AwardsOverview {
        try await NorthAPI.call { try await api.getAwards().ok.body.json }
    }

    func unseen() async throws -> [Award] {
        try await NorthAPI.call { try await api.getUnseenAwards().ok.body.json.awards }
    }

    func markSeen(_ badgeID: String) async throws {
        try await NorthAPI.call { _ = try await api.markAwardSeen(path: .init(badgeID: badgeID)).noContent }
    }
}
