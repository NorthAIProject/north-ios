import Foundation
import NorthAPI

protocol HorizonServicing: Sendable {
    /// The forecast under a what-if; the plain one for `HorizonScenario()`.
    func forecast(_ scenario: HorizonScenario) async throws -> Components.Schemas.Horizon
    /// One lift with the history behind its forecast, by its key from the forecast.
    func lift(_ key: String) async throws -> Components.Schemas.HorizonLiftDetail
}

/// Where a workout asks what each lift's next set could be.
protocol NextSetServicing: Sendable {
    /// A suggestion per key that has enough history; the rest are absent.
    func nextSets(_ keys: [String]) async throws -> [String: NextSet]
}

struct HorizonService: HorizonServicing, NextSetServicing {
    /// The most keys one request takes.
    static let maxNextSetKeys = 20

    var api: Client = API.shared

    func forecast(_ scenario: HorizonScenario) async throws -> Components.Schemas.Horizon {
        let query = Operations.GetHorizon.Input.Query(
            skipWeeks: scenario.skipWeeks,
            extraSessions: scenario.extraSession ? 1 : 0,
            deloadNow: scenario.deloadNow
        )
        return try await NorthAPI.call { try await api.getHorizon(query: query).ok.body.json }
    }

    func lift(_ key: String) async throws -> Components.Schemas.HorizonLiftDetail {
        try await NorthAPI.call { try await api.getHorizonLift(path: .init(key: key)).ok.body.json }
    }

    func nextSets(_ keys: [String]) async throws -> [String: NextSet] {
        // The keys travel comma separated, so a name with a comma cannot be asked for.
        let asked = keys.filter { !$0.isEmpty && !$0.contains(",") }.prefix(Self.maxNextSetKeys)
        guard !asked.isEmpty else { return [:] }
        let query = Operations.GetHorizonNextSets.Input.Query(keys: asked.joined(separator: ","))
        let response = try await NorthAPI.call { try await api.getHorizonNextSets(query: query).ok.body.json }
        return Dictionary(
            response.sets.map { ($0.key, NextSet(weightKg: $0.weightKg, reps: $0.reps, reason: $0.reasonText)) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
