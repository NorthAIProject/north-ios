import Foundation
import NorthAPI

typealias Crew = Components.Schemas.Crew
typealias CrewBoard = Components.Schemas.CrewBoard
typealias CrewMember = Components.Schemas.CrewMember
typealias CrewChallenge = Components.Schemas.CrewChallenge

protocol CrewsServicing: Sendable {
    func crews() async throws -> [Crew]
    func create(name: String) async throws -> Crew
    func join(code: String) async throws -> Crew
    func board(_ crewID: String) async throws -> CrewBoard
    /// Your own id leaves; another member's id removes them (owner only).
    func remove(_ crewID: String, member: String) async throws
    func setChallenge(_ crewID: String, _ challenge: CrewChallenge?) async throws
}

struct CrewsService: CrewsServicing {
    var api: Client = API.shared

    func crews() async throws -> [Crew] {
        try await NorthAPI.call { try await api.listCrews().ok.body.json.crews }
    }

    func create(name: String) async throws -> Crew {
        try await NorthAPI.call { try await api.createCrew(body: .json(.init(name: name))).created.body.json }
    }

    func join(code: String) async throws -> Crew {
        try await NorthAPI.call { try await api.joinCrew(path: .init(code: code)).ok.body.json }
    }

    func board(_ crewID: String) async throws -> CrewBoard {
        try await NorthAPI.call { try await api.getCrewBoard(path: .init(crewID: crewID)).ok.body.json }
    }

    func remove(_ crewID: String, member: String) async throws {
        try await NorthAPI.call { _ = try await api.removeCrewMember(path: .init(crewID: crewID, userID: member)).noContent }
    }

    func setChallenge(_ crewID: String, _ challenge: CrewChallenge?) async throws {
        if let challenge {
            try await NorthAPI.call { _ = try await api.setCrewChallenge(path: .init(crewID: crewID), body: .json(challenge)).ok }
        } else {
            try await NorthAPI.call { _ = try await api.clearCrewChallenge(path: .init(crewID: crewID)).noContent }
        }
    }
}

/// A crew link opened before it could be used, kept until there is a session.
enum PendingCrewJoin {
    private static let key = "crew.pending"

    static func store(_ code: String) { UserDefaults.standard.set(code, forKey: key) }

    static func take() -> String? {
        guard let code = UserDefaults.standard.string(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return code
    }

    /// Joins a stored crew, if any, and returns it. A failure keeps the code.
    static func joinIfAny(using service: CrewsServicing = CrewsService()) async -> Crew? {
        guard let code = take() else { return nil }
        do {
            return try await service.join(code: code)
        } catch {
            store(code)
            return nil
        }
    }
}
