import Foundation
import NorthAPI

typealias InsightsSummary = Components.Schemas.InsightsSummary
typealias InsightMetric = Components.Schemas.InsightMetric
typealias InsightsChart = Components.Schemas.InsightsChart

protocol InsightsServicing: Sendable {
    func summary(range: String?) async throws -> InsightsSummary
    func metric(_ key: String, range: String?) async throws -> InsightMetric
}

struct InsightsService: InsightsServicing {
    var api: Client = API.shared

    func summary(range: String?) async throws -> InsightsSummary {
        try await NorthAPI.call { try await api.getInsights(query: .init(range: range)).ok.body.json }
    }

    func metric(_ key: String, range: String?) async throws -> InsightMetric {
        try await NorthAPI.call { try await api.getInsightMetric(path: .init(key: key), query: .init(range: range)).ok.body.json }
    }
}

/// The Progress tab: every domain's score for a window.
@MainActor
@Observable
final class InsightsStore {
    enum Phase: Equatable { case loading, failed(String), ready }

    private(set) var phase: Phase = .loading
    private(set) var summary: InsightsSummary?
    /// The window shown. Starts on the last seven days, which is the most a
    /// person can take in at a glance; the server's own default is today.
    var range = "week"

    let service: InsightsServicing

    init(service: InsightsServicing = InsightsService()) {
        self.service = service
    }

    func load() async {
        if summary == nil { phase = .loading }
        do {
            summary = try await service.summary(range: range)
            phase = .ready
        } catch {
            if summary == nil { phase = .failed(error.localizedDescription) }
        }
    }
}

/// The health metrics the phone syncs, each with its own detail page.
enum HealthMetric: String, CaseIterable, Identifiable {
    case steps
    case activeEnergy = "active-energy"
    case restingHeartRate = "resting-heart-rate"
    case hrv

    var id: String { rawValue }

    var label: String {
        switch self {
        case .steps: "Steps"
        case .activeEnergy: "Active Energy"
        case .restingHeartRate: "Resting Heart Rate"
        case .hrv: "Heart Rate Variability"
        }
    }

    var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .activeEnergy: "flame"
        case .restingHeartRate: "heart"
        case .hrv: "waveform.path.ecg"
        }
    }
}
