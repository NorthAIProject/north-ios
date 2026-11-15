import Foundation
import NorthAPI
import Testing
@testable import khepri

/// The bug this exists for: PlanSummary.source was a closed enum of ai and
/// edited. The server stores plans imported from a file as "imported", and one
/// such plan made the whole /training/plans list undecodable, so the Training
/// tab said "Training did not load".
struct PlanSourceDecodeTests {
    private func decode(_ source: String, origin: String? = nil) throws -> PlanSummary {
        var json: [String: Any] = [
            "id": "p1", "name": "Strength 4-day", "weeksTotal": 4, "days": [],
            "source": source, "createdAt": "2026-11-14T17:24:22Z",
        ]
        if let origin { json["origin"] = origin }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PlanSummary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func anUnknownSourceStillDecodes() throws {
        let plan = try decode("imported")
        #expect(plan.source == "imported")
    }

    @Test func originIsReadWhenPresent() throws {
        let plan = try decode("edited", origin: "imported")
        #expect(plan.origin == "imported")
    }

    @Test func originIsOptionalForOlderServers() throws {
        let plan = try decode("ai")
        #expect(plan.origin == nil)
    }
}
