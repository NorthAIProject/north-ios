import Foundation
import NorthAPI
import Observation

/// The forecast on screen: which what-if, which day, and the last answer.
///
/// The day being looked at survives a what-if, so flipping one shows what it
/// changes on that day rather than snapping back to today.
@MainActor
@Observable
final class HorizonStore {
    private(set) var forecast: HorizonForecast?
    private(set) var isLoading = false
    private(set) var failure: String?
    private(set) var scenario = HorizonScenario()
    /// Index into the forecast's frames.
    var frameIndex = 0

    @ObservationIgnored private let service: any HorizonServicing
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(service: any HorizonServicing = HorizonService()) {
        self.service = service
    }

    var frame: HorizonFrame? {
        guard let frames = forecast?.frames, !frames.isEmpty else { return nil }
        return frames[min(frameIndex, frames.count - 1)]
    }

    var offsetDays: Int { frame?.offsetDays ?? 0 }

    func load() async {
        await fetch(scenario)
    }

    /// Changes the what-if and reloads. A newer change replaces one still
    /// loading, so the last tap is what ends up on screen.
    func set(_ change: (inout HorizonScenario) -> Void) {
        var next = scenario
        change(&next)
        next.skipWeeks = min(max(next.skipWeeks, 0), HorizonScenario.maxSkipWeeks)
        guard next != scenario else { return }
        scenario = next
        loading?.cancel()
        loading = Task { await fetch(next) }
    }

    private func fetch(_ wanted: HorizonScenario) async {
        isLoading = true
        defer { if wanted == scenario { isLoading = false } }
        do {
            let response = try await service.forecast(wanted)
            // Answers can arrive out of order; only the current what-if's counts.
            guard wanted == scenario, !Task.isCancelled else { return }
            forecast = HorizonForecast(
                response,
                weightName: String(localized: "Body weight"),
                waistName: String(localized: "Waist"),
                liftMeasure: String(localized: "Est. 1RM")
            )
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            guard wanted == scenario else { return }
            failure = error.localizedDescription
        }
    }
}
