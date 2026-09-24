import Foundation
import NorthAPI

typealias CheckIn = Components.Schemas.CheckIn
typealias CheckInList = Components.Schemas.CheckInList
typealias CheckInRequest = Components.Schemas.CheckInRequest

protocol CheckInsServicing: Sendable {
    func checkIns() async throws -> CheckInList
    func saveToday(_ request: CheckInRequest) async throws -> CheckIn
    func delete(_ id: String) async throws
}

struct CheckInsService: CheckInsServicing {
    var api: Client = API.shared

    func checkIns() async throws -> CheckInList {
        try await NorthAPI.call { try await api.listCheckIns().ok.body.json }
    }

    func saveToday(_ request: CheckInRequest) async throws -> CheckIn {
        try await NorthAPI.call { try await api.saveTodayCheckIn(body: .json(request)).ok.body.json }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteCheckIn(path: .init(checkInID: id)).noContent }
    }
}
