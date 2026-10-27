import Foundation
import NorthAPI

typealias CheckIn = Components.Schemas.CheckIn
typealias CheckInList = Components.Schemas.CheckInList
typealias CheckInRequest = Components.Schemas.CheckInRequest
typealias SavedCheckIn = Components.Schemas.SavedCheckIn
typealias CheckInReply = Components.Schemas.CheckInReply

protocol CheckInsServicing: Sendable {
    func checkIns() async throws -> CheckInList
    /// Files today's check-in, and says what the save meant for the run.
    func saveToday(_ request: CheckInRequest) async throws -> SavedCheckIn
    /// Edits an earlier day's check-in, such as the goal it was about.
    func update(_ id: String, _ request: CheckInRequest) async throws -> CheckIn
    func delete(_ id: String) async throws
    /// The coach's note under today's check-in, or nil when there is none to
    /// show. Never throws: the note is decoration.
    func reply() async -> CheckInReply?
}

struct CheckInsService: CheckInsServicing {
    var api: Client = API.shared

    func checkIns() async throws -> CheckInList {
        try await NorthAPI.call { try await api.listCheckIns().ok.body.json }
    }

    func saveToday(_ request: CheckInRequest) async throws -> SavedCheckIn {
        try await NorthAPI.call { try await api.saveTodayCheckIn(body: .json(request)).ok.body.json }
    }

    func update(_ id: String, _ request: CheckInRequest) async throws -> CheckIn {
        try await NorthAPI.call { try await api.updateCheckIn(path: .init(checkInID: id), body: .json(request)).ok.body.json }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteCheckIn(path: .init(checkInID: id)).noContent }
    }

    func reply() async -> CheckInReply? {
        guard case let .ok(ok) = try? await api.replyToTodayCheckIn() else { return nil }
        return try? ok.body.json
    }
}
