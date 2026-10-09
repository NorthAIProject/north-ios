import Foundation
import NorthAPI

typealias InsightsSummary = Components.Schemas.InsightsSummary
typealias InsightMetric = Components.Schemas.InsightMetric
typealias InsightsChart = Components.Schemas.InsightsChart
typealias InsightsHealthMetric = Components.Schemas.InsightsHealthMetric
typealias InsightsUsualRange = Components.Schemas.InsightsUsualRange

protocol InsightsServicing: Sendable {
    func summary(range: String?) async throws -> InsightsSummary
    func metric(_ key: String, range: String?) async throws -> InsightMetric
    func health() async throws -> [InsightsHealthMetric]
}

struct InsightsService: InsightsServicing {
    var api: Client = API.shared

    func summary(range: String?) async throws -> InsightsSummary {
        try await NorthAPI.call { try await api.getInsights(query: .init(range: range)).ok.body.json }
    }

    func metric(_ key: String, range: String?) async throws -> InsightMetric {
        try await NorthAPI.call { try await api.getInsightMetric(path: .init(key: key), query: .init(range: range)).ok.body.json }
    }

    func health() async throws -> [InsightsHealthMetric] {
        try await NorthAPI.call { try await api.getInsightsHealth().ok.body.json.metrics }
    }
}

/// The Progress tab: every domain's score for a window.
@MainActor
@Observable
final class InsightsStore {
    enum Phase: Equatable { case loading, failed(String), ready }

    private(set) var phase: Phase = .loading
    private(set) var summary: InsightsSummary?
    /// The health metrics the server says this person tracks. The list is the
    /// server's, so a new metric appears here without an app update.
    private(set) var health: [InsightsHealthMetric] = []
    /// The window shown. Starts on the last seven days, which is the most a
    /// person can take in at a glance; the server's own default is today.
    var range = "week"

    let service: InsightsServicing

    init(service: InsightsServicing = InsightsService()) {
        self.service = service
    }

    func load() async {
        if summary == nil { phase = .loading }
        async let latestHealth = service.health()
        do {
            summary = try await service.summary(range: range)
            phase = .ready
        } catch {
            if summary == nil { phase = .failed(error.localizedDescription) }
        }
        // Health is a section, not the screen: if it fails, the rest still
        // shows and the last list stays.
        if let latest = try? await latestHealth { health = latest }
    }
}
