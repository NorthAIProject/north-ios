import Foundation
import NorthAPI
import Testing
@testable import khepri

private struct StubConsentService: AIConsentServicing {
    var status: String
    var failsToSave = false

    func consent() async throws -> Components.Schemas.AIConsent {
        .init(status: status, version: 1, recipients: ["Anthropic"])
    }

    func decide(allow: Bool) async throws -> Components.Schemas.AIConsent {
        if failsToSave { throw APIError.server("Nope") }
        return .init(status: allow ? "granted" : "declined", version: 1, recipients: ["Anthropic"])
    }
}

@MainActor
struct AIConsentCenterTests {
    @Test func unansweredAccountIsAsked() async {
        let center = AIConsentCenter(service: StubConsentService(status: "unset"))
        #expect(!center.needsAnswer)
        await center.load()
        #expect(center.needsAnswer)
        #expect(center.recipients == ["Anthropic"])
    }

    @Test func decidingStopsTheQuestion() async {
        let center = AIConsentCenter(service: StubConsentService(status: "unset"))
        await center.load()
        await center.decide(allow: false)
        #expect(center.choice == .declined)
        #expect(!center.needsAnswer)
        await center.decide(allow: true)
        #expect(center.choice == .allowed)
    }

    @Test func aStatusThisBuildDoesNotKnowDoesNotAsk() async {
        let center = AIConsentCenter(service: StubConsentService(status: "paused"))
        await center.load()
        #expect(center.choice == .unknown)
        #expect(!center.needsAnswer)
    }

    @Test func aFailedSaveKeepsTheQuestionOpen() async {
        let center = AIConsentCenter(service: StubConsentService(status: "unset", failsToSave: true))
        await center.load()
        await center.decide(allow: true)
        #expect(center.needsAnswer)
        #expect(center.saveError == "Nope")
    }
}
