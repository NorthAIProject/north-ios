import Foundation
import NorthAPI

typealias FormCheck = Components.Schemas.FormCheck

protocol FormCheckServicing: Sendable {
    func checks() async throws -> [FormCheck]
    func check(_ id: String) async throws -> FormCheck
}

struct FormCheckService: FormCheckServicing {
    var api: Client = API.shared

    func checks() async throws -> [FormCheck] {
        try await NorthAPI.call { try await api.listFormChecks().ok.body.json.checks }
    }

    func check(_ id: String) async throws -> FormCheck {
        try await NorthAPI.call { try await api.getFormCheck(path: .init(analysisID: id)).ok.body.json }
    }
}
