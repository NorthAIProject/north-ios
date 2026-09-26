import Foundation
import NorthAPI

typealias LiftSet = Components.Schemas.LiftSet
typealias LiftStats = Components.Schemas.LiftStats

/// Sets as they are lifted: the weight and reps of each, the last workout's
/// numbers to start from, and the stats built on them.
protocol LiftServicing: Sendable {
    /// The last workout's sets per exercise key, for the keys that have one.
    func last(_ keys: [String]) async throws -> [String: [LiftSet]]
    func log(_ input: Components.Schemas.LiftSetInput) async throws -> LiftSet
    func delete(_ id: String) async throws
    func stats(range: String) async throws -> LiftStats
}

struct LiftService: LiftServicing {
    var api: Client = API.shared

    func last(_ keys: [String]) async throws -> [String: [LiftSet]] {
        guard !keys.isEmpty else { return [:] }
        let body = try await NorthAPI.call { try await api.getLastLifts(query: .init(exercise: keys)).ok.body.json }
        return Dictionary(body.exercises.map { ($0.key, $0.sets) }, uniquingKeysWith: { first, _ in first })
    }

    func log(_ input: Components.Schemas.LiftSetInput) async throws -> LiftSet {
        try await NorthAPI.call { try await api.logLiftSet(body: .json(input)).created.body.json }
    }

    func delete(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteLiftSet(path: .init(setID: id)).noContent }
    }

    func stats(range: String) async throws -> LiftStats {
        try await NorthAPI.call { try await api.getLiftStats(query: .init(range: range)).ok.body.json }
    }
}

/// The arithmetic the server does too, for what the workout shows before
/// the server has answered.
enum LiftMath {
    /// Matches the server's key: the catalog slug, or the trimmed,
    /// lower-cased name.
    static func key(slug: String?, name: String) -> String {
        if let slug, !slug.isEmpty { return slug }
        return name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Epley's estimated one-rep max. A single is its own max.
    static func e1rm(weightKg: Double, reps: Int) -> Double {
        reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// The first number in a prescription like "8-12" or "10 each side".
    static func reps(from prescription: String) -> Int? {
        let digits = prescription.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    static let poundsPerKg = 2.20462

    /// A weight for display, in the units the person uses.
    static func display(_ kg: Double, imperial: Bool) -> Double {
        let value = imperial ? kg * poundsPerKg : kg
        return (value * 10).rounded() / 10
    }

    static func kilograms(_ value: Double, imperial: Bool) -> Double {
        imperial ? value / poundsPerKg : value
    }
}
