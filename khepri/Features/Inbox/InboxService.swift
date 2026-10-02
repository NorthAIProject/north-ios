import Foundation
import NorthAPI

typealias InboxItem = Components.Schemas.InboxItem
typealias InboxSuggestion = Components.Schemas.InboxSuggestion

/// Where an inbox item can be filed.
enum InboxDestination: String, CaseIterable, Identifiable {
    case goalNote = "goal_note", knowledge, journal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goalNote: "Goal Note"
        case .knowledge: "Knowledge"
        case .journal: "Journal"
        }
    }

    var systemImage: String {
        switch self {
        case .goalNote: "target"
        case .knowledge: "books.vertical"
        case .journal: "book"
        }
    }
}

protocol InboxServicing: Sendable {
    /// What is waiting, newest first, and how many in all.
    func inbox() async throws -> (items: [InboxItem], open: Int)
    func add(_ text: String) async throws
    func file(_ id: String, to destination: InboxDestination, goalID: String?, title: String?) async throws
    func dismiss(_ id: String) async throws
}

struct InboxService: InboxServicing {
    var api: Client = API.shared

    func inbox() async throws -> (items: [InboxItem], open: Int) {
        let body = try await NorthAPI.call { try await api.listInbox().ok.body.json }
        return (body.items, body.open)
    }

    func add(_ text: String) async throws {
        try await NorthAPI.call { _ = try await api.addToInbox(body: .json(.init(text: text, source: .app))).created }
    }

    func file(_ id: String, to destination: InboxDestination, goalID: String?, title: String?) async throws {
        let body = Operations.FileInboxItem.Input.Body.JsonPayload(
            destination: .init(rawValue: destination.rawValue) ?? .journal,
            goalId: goalID,
            title: title
        )
        try await NorthAPI.call { _ = try await api.fileInboxItem(path: .init(itemID: id), body: .json(body)).ok }
    }

    func dismiss(_ id: String) async throws {
        try await NorthAPI.call { _ = try await api.dismissInboxItem(path: .init(itemID: id)).noContent }
    }
}

extension InboxSuggestion {
    /// The suggested destination as the app names it.
    var home: InboxDestination? { InboxDestination(rawValue: destination.rawValue) }

    /// The suggestion in a few words: "A note on Run a half marathon".
    var label: String {
        switch home {
        case .goalNote: "A note on \(goalTitle ?? "a goal")"
        case .knowledge: title.map { "Knowledge: \($0)" } ?? "Knowledge"
        case .journal, nil: "Journal"
        }
    }
}
