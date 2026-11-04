import Foundation
import NorthAPI
import Observation

protocol AIConsentServicing: Sendable {
    func consent() async throws -> Components.Schemas.AIConsent
    func decide(allow: Bool) async throws -> Components.Schemas.AIConsent
}

struct AIConsentService: AIConsentServicing {
    var api: Client = API.shared

    func consent() async throws -> Components.Schemas.AIConsent {
        try await NorthAPI.call { try await api.getAIConsent().ok.body.json }
    }

    func decide(allow: Bool) async throws -> Components.Schemas.AIConsent {
        try await NorthAPI.call {
            try await api.setAIConsent(body: .json(.init(decision: allow ? "granted" : "declined"))).ok.body.json
        }
    }
}

/// Whether this account allows its data to go to third-party AI providers.
/// The server enforces the answer; this decides which screens to show.
@MainActor
@Observable
final class AIConsentCenter {
    enum Choice: Equatable {
        /// Not loaded yet, or the server sent a status this build does not know.
        case unknown
        case unanswered
        case allowed
        case declined
    }

    private(set) var choice: Choice = .unknown
    private(set) var recipients: [String] = []
    private(set) var isSaving = false
    private(set) var saveError: String?

    private let service: AIConsentServicing

    init(service: AIConsentServicing = AIConsentService()) {
        self.service = service
    }

    var needsAnswer: Bool { choice == .unanswered }

    func load() async {
        guard choice == .unknown else { return }
        if let consent = try? await service.consent() {
            apply(consent)
        }
    }

    func decide(allow: Bool) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            apply(try await service.decide(allow: allow))
        } catch {
            saveError = error.localizedDescription
        }
    }

    func reset() {
        choice = .unknown
        recipients = []
        saveError = nil
    }

    private func apply(_ consent: Components.Schemas.AIConsent) {
        recipients = consent.recipients
        switch consent.status {
        case "unset": choice = .unanswered
        case "granted": choice = .allowed
        case "declined": choice = .declined
        default: choice = .unknown
        }
    }
}
