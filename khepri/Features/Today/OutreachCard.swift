import NorthAPI
import NorthKit
import SwiftUI

typealias Outreach = Components.Schemas.Outreach

/// The coach's one unprompted message of the day: it noticed something (a
/// low-recovery morning, a missed session) and spoke first.
protocol OutreachServicing: Sendable {
    func today() async throws -> Outreach?
    /// id is the message's, or "today", which is what a notification button
    /// sends: the banner knows the day but not the message.
    func answer(id: String, action: String) async throws -> Outreach
}

struct OutreachService: OutreachServicing {
    var api: Client = API.shared

    func today() async throws -> Outreach? {
        try await NorthAPI.call { try await api.getOutreachToday().ok.body.json }.outreach
    }

    func answer(id: String, action: String) async throws -> Outreach {
        try await NorthAPI.call {
            try await api.answerOutreach(path: .init(id: id), body: .json(.init(action: action))).ok.body.json
        }
    }
}

extension Outreach {
    /// A low morning the coach spoke about: its message carries the lighter-day
    /// answers, so the lighter-day card stays out of the way.
    var coversRecovery: Bool { trigger == "low_recovery" }

    static func title(forAction action: String) -> String {
        switch action {
        case "undo": String(localized: "Undo", comment: "Answer to the coach's message: put back the session it lightened")
        case "lighter": String(localized: "Take It Lighter")
        case "keep": String(localized: "Keep the Plan")
        case "today": String(localized: "Do It Today", comment: "Answer to the coach's message about a missed session")
        case "tomorrow": String(localized: "Tomorrow", comment: "Answer to the coach's message about a missed session")
        case "let_go": String(localized: "Let It Go", comment: "Answer to the coach's message about a missed session")
        default: action
        }
    }
}

/// Today's message, loaded by the Today screen, which also asks it whether to
/// show the lighter-day card.
@MainActor
@Observable
final class OutreachStore {
    private(set) var message: Outreach?
    private(set) var saving = false
    private(set) var error: String?
    private let service: OutreachServicing

    init(service: OutreachServicing = OutreachService()) {
        self.service = service
    }

    func load() async {
        if let latest = try? await service.today() { message = latest }
    }

    func answer(_ action: String) async {
        guard let message else { return }
        saving = true
        defer { saving = false }
        do {
            self.message = try await service.answer(id: message.id, action: action)
            error = nil
        } catch {
            self.error = error.localizedDescription
            // Answered elsewhere already (a notification button, Telegram):
            // show what is true now.
            await load()
        }
    }
}

/// "From your coach": the message, and the answers it offers, or what the
/// answer did. Shows nothing on a day the coach did not speak first.
struct OutreachCard: View {
    let store: OutreachStore

    var body: some View {
        if let message = store.message {
            VStack(alignment: .leading, spacing: 10) {
                Label("From Your Coach", systemImage: "bubble.left")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.tint)
                Text(message.body)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = store.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if !message.actions.isEmpty {
                    HStack {
                        ForEach(Array(message.actions.enumerated()), id: \.element) { index, action in
                            if index == 0 {
                                Button(Outreach.title(forAction: action)) { Task { await store.answer(action) } }
                                    .northProminentButton()
                            } else {
                                Button(Outreach.title(forAction: action)) { Task { await store.answer(action) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    .disabled(store.saving)
                } else if let outcome = message.outcome {
                    Label(outcome, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .northSurfaceCard(padding: 16)
            .accessibilityIdentifier("coach-outreach")
        }
    }
}
