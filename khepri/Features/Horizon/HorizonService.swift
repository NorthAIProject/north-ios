import Foundation
import NorthAPI

protocol HorizonServicing: Sendable {
    /// The forecast under a what-if; the plain one for `HorizonScenario()`.
    func forecast(_ scenario: HorizonScenario) async throws -> Components.Schemas.Horizon
}

struct HorizonService: HorizonServicing {
    var api: Client = API.shared

    func forecast(_ scenario: HorizonScenario) async throws -> Components.Schemas.Horizon {
        let query = Operations.GetHorizon.Input.Query(
            skipWeeks: scenario.skipWeeks,
            extraSessions: scenario.extraSession ? 1 : 0,
            deloadNow: scenario.deloadNow
        )
        return try await NorthAPI.call { try await api.getHorizon(query: query).ok.body.json }
    }
}
