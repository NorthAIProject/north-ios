import Foundation
import NorthAPI
import Observation

/// The progress-check screen's state: the checks so far, the reminder, the
/// first-versus-latest comparison, and where photos would go for an estimate.
@MainActor
@Observable
final class ProgressCheckStore {
    private(set) var list: ProgressChecks?
    /// nil until loaded; a failure leaves the manual form only.
    private(set) var assist: ProgressAssist?
    private(set) var error: String?
    private(set) var comparing = false
    private(set) var compareError: String?

    private let service: ProgressCheckServicing

    init(service: ProgressCheckServicing = ProgressCheckService()) {
        self.service = service
    }

    var checks: [ProgressCheck] { list?.checks ?? [] }
    var schedule: ProgressSchedule? { list?.schedule }
    var canEstimate: Bool { assist?.available == true }

    func load() async {
        async let loadedAssist = try? service.assist()
        do {
            list = try await service.checks()
            error = nil
        } catch {
            if list == nil { self.error = error.localizedDescription }
        }
        if let fresh = await loadedAssist { assist = fresh }
    }

    /// Saves a check and reloads, so the history, the reminder and the
    /// comparison's staleness all follow it. Throws for the form to show.
    func save(_ draft: ProgressCheckDraft, photos: ProgressPhotos) async throws {
        _ = try await service.save(draft.input(), photos: photos)
        await load()
    }

    func estimate(_ photos: ProgressPhotos) async throws -> ProgressEstimateResult {
        try await service.estimate(photos)
    }

    func compare() async {
        comparing = true
        defer { comparing = false }
        do {
            _ = try await service.compare()
            compareError = nil
            await load()
        } catch {
            compareError = error.localizedDescription
        }
    }

    func delete(_ check: ProgressCheck) async {
        do {
            list = try await service.delete(check.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setCadence(_ cadence: String) async {
        do {
            let schedule = try await service.setCadence(cadence)
            list?.schedule = schedule
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The check before this one in time, for the history's changes.
    func older(than check: ProgressCheck) -> ProgressCheck? {
        guard let index = checks.firstIndex(where: { $0.id == check.id }), index + 1 < checks.count else { return nil }
        return checks[index + 1]
    }
}
