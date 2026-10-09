import Foundation
import NorthAPI
import Testing
@testable import khepri

private struct FakeInsights: InsightsServicing {
    var healthError: Error?

    func summary(range: String?) async throws -> InsightsSummary {
        let json = #"{"range":{"key":"week","label":"Last 7 days","options":[]},"scores":[],"pinned":[],"highlights":[],"onTrack":0,"judged":0,"empty":true}"#
        return try JSONDecoder().decode(InsightsSummary.self, from: Data(json.utf8))
    }

    func metric(_ key: String, range: String?) async throws -> InsightMetric {
        throw URLError(.unsupportedURL)
    }

    func health() async throws -> [InsightsHealthMetric] {
        if let healthError { throw healthError }
        return [
            .init(key: "steps", label: "Steps", latest: "9400", day: "2026-10-08", recent: [8800, 9400],
                  usual: .init(day: "2026-10-08", latest: 9400, mean: 9000, sd: 900, low: "8100", high: "9900",
                               days: 28, z: 0.44, state: "usual", text: "Within your usual range: 9400 on Thu 8 Oct, usually 8100–9900.")),
            .init(key: "a-metric-from-a-later-server", label: "Something New", latest: "3", day: "2026-10-08", recent: [3]),
        ]
    }
}

@MainActor
struct InsightsStoreTests {
    @Test func theHealthListIsTheServers() async {
        let store = InsightsStore(service: FakeInsights())
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.health.map(\.key) == ["steps", "a-metric-from-a-later-server"])
        #expect(store.health.first?.usual?.state == "usual")
    }

    @Test func aHealthFailureLeavesTheRestOfTheScreen() async {
        let store = InsightsStore(service: FakeInsights(healthError: URLError(.notConnectedToInternet)))
        await store.load()
        #expect(store.phase == .ready)
        #expect(store.health.isEmpty)
    }

    @Test func anUnknownKeyStillGetsASymbol() {
        #expect(HealthSymbol.name(for: "steps") == "figure.walk")
        #expect(HealthSymbol.name(for: "a-metric-from-a-later-server") == "heart.text.square")
    }
}
