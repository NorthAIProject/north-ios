import Foundation
import NorthAPI

/// Everything My Day can log. Each call goes to the slice that owns it; the
/// store reloads the day afterwards rather than patching it by hand.
protocol DayActing: Sendable {
    func logWater(_ ml: Int) async throws
    func logCaffeine(preset: String) async throws
    func logSupplement(preset: String, count: Int) async throws
    func startFast(hours: Int) async throws
    func stopFast() async throws
    func setScreenTime(minutes: Int) async throws
    func setSoreness(region: String, severity: Int) async throws
    func clearSoreness(region: String) async throws
    func recordBloodPressure(systolic: Int, diastolic: Int) async throws
    func setTargetWeight(_ kg: Double?) async throws
    func createTracker(name: String, lastDone: Date?) async throws
    func trackerDone(id: String) async throws
}

struct DayActions: DayActing {
    var api: Client = API.shared

    func logWater(_ ml: Int) async throws {
        _ = try await NorthAPI.call { try await api.logWater(body: .json(.init(amountMl: ml))).created.body.json }
    }
    func logCaffeine(preset: String) async throws {
        _ = try await NorthAPI.call { try await api.logCaffeine(body: .json(.init(preset: preset))).created.body.json }
    }
    func logSupplement(preset: String, count: Int) async throws {
        _ = try await NorthAPI.call { try await api.logSupplement(body: .json(.init(preset: preset, count: count))).created.body.json }
    }
    func startFast(hours: Int) async throws {
        _ = try await NorthAPI.call { try await api.startFast(body: .json(.init(targetHours: hours))).created.body.json }
    }
    func stopFast() async throws {
        _ = try await NorthAPI.call { try await api.stopFast().ok.body.json }
    }
    func setScreenTime(minutes: Int) async throws {
        _ = try await NorthAPI.call { try await api.setScreenTime(body: .json(.init(minutes: minutes, source: .manual))).ok.body.json }
    }
    func setSoreness(region: String, severity: Int) async throws {
        _ = try await NorthAPI.call {
            try await api.setSoreness(path: .init(region: region), body: .json(.init(severity: severity))).ok.body.json
        }
    }
    func clearSoreness(region: String) async throws {
        _ = try await NorthAPI.call { try await api.clearSoreness(path: .init(region: region)).ok.body.json }
    }
    func recordBloodPressure(systolic: Int, diastolic: Int) async throws {
        _ = try await NorthAPI.call {
            try await api.recordBloodPressure(body: .json(.init(systolic: systolic, diastolic: diastolic))).created.body.json
        }
    }
    func setTargetWeight(_ kg: Double?) async throws {
        _ = try await NorthAPI.call { try await api.setTargetWeight(body: .json(.init(targetWeightKg: kg))).ok.body.json }
    }
    func createTracker(name: String, lastDone: Date?) async throws {
        _ = try await NorthAPI.call {
            try await api.createTracker(body: .json(.init(name: name, lastDoneOn: lastDone.map(CalendarDay.string(from:))))).created.body.json
        }
    }
    func trackerDone(id: String) async throws {
        _ = try await NorthAPI.call { try await api.markTrackerDone(path: .init(id: id)).ok.body.json }
    }
}
