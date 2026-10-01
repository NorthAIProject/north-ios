import Foundation
import NorthAPI

typealias CaptureItem = Components.Schemas.CaptureItem

/// What the model read in one sentence. `unparsed` holds the parts it could
/// not place, so the person can see what was left out rather than guess.
struct CaptureReading: Sendable {
    var items: [CaptureItem]
    var unparsed: [String] = []
}

/// How many of the committed items the server saved.
struct CaptureOutcome: Sendable, Equatable {
    var written: Int
    var failed: Int
}

/// "Drank 500 ml and slept 7 hours" in two steps: read the sentence, then
/// write only what the person confirmed. Shared by the Siri intent and the
/// in-app composer so both go through the same preview-then-write rule.
protocol CaptureServicing: Sendable {
    func parse(_ text: String) async throws -> CaptureReading
    func commit(_ items: [CaptureItem]) async throws -> CaptureOutcome
}

struct CaptureService: CaptureServicing {
    var api: Client = API.shared

    func parse(_ text: String) async throws -> CaptureReading {
        let parsed = try await NorthAPI.call { try await api.parseCapture(body: .json(.init(text: text))).ok.body.json }
        return CaptureReading(items: parsed.items, unparsed: parsed.unparsed)
    }

    func commit(_ items: [CaptureItem]) async throws -> CaptureOutcome {
        let result = try await NorthAPI.call { try await api.commitCapture(body: .json(.init(items: items))).ok.body.json }
        return CaptureOutcome(written: result.written, failed: result.failed)
    }
}
