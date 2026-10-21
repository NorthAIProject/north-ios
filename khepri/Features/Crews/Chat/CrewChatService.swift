import Foundation
import NorthAPI
import OpenAPIRuntime

typealias CrewSpace = Components.Schemas.CrewSpace
typealias CrewChannel = Components.Schemas.CrewChannel
typealias CrewMessage = Components.Schemas.CrewMessage

protocol CrewChatServicing: Sendable {
    func space(_ crewID: String) async throws -> CrewSpace
    func messages(_ crewID: String, channel: String, before: Int64?, after: Int64?) async throws -> Components.Schemas.CrewMessagePage
    func message(_ crewID: String, id: String) async throws -> CrewMessage
    func send(_ crewID: String, channel: String, body: String, replyTo: String?, clientID: UUID) async throws -> CrewMessage
    func edit(_ crewID: String, id: String, body: String) async throws -> CrewMessage
    func delete(_ crewID: String, id: String) async throws
    func react(_ crewID: String, id: String, emoji: String, on: Bool) async throws
    func pin(_ crewID: String, id: String, on: Bool) async throws
    func pins(_ crewID: String, channel: String) async throws -> [CrewMessage]
    func markRead(_ crewID: String, channel: String, seq: Int64) async throws
    func report(_ crewID: String, id: String, reason: String, note: String?) async throws
    func setNotify(_ crewID: String, notify: String, mutedUntil: Date?) async throws
    func unread() async throws -> Components.Schemas.CrewUnreadList
    func termsAccepted() async throws -> Bool
    func acceptTerms() async throws
    func block(_ userID: String) async throws
    /// The crew's live events as Server-Sent Events (`text/event-stream`).
    func live(_ crewID: String) async throws -> HTTPBody
}

struct CrewChatService: CrewChatServicing {
    var api: Client = API.shared

    func space(_ crewID: String) async throws -> CrewSpace {
        try await NorthAPI.call { try await api.getCrewSpace(path: .init(crewID: crewID)).ok.body.json }
    }

    func messages(_ crewID: String, channel: String, before: Int64?, after: Int64?) async throws -> Components.Schemas.CrewMessagePage {
        try await NorthAPI.call {
            try await api.listCrewMessages(
                path: .init(crewID: crewID, channelID: channel),
                query: .init(before: before, after: after)
            ).ok.body.json
        }
    }

    func message(_ crewID: String, id: String) async throws -> CrewMessage {
        try await NorthAPI.call { try await api.getCrewMessage(path: .init(crewID: crewID, messageID: id)).ok.body.json }
    }

    func send(_ crewID: String, channel: String, body: String, replyTo: String?, clientID: UUID) async throws -> CrewMessage {
        try await NorthAPI.call {
            try await api.sendCrewMessage(
                path: .init(crewID: crewID, channelID: channel),
                body: .json(.init(body: body, replyToId: replyTo, clientId: clientID.uuidString))
            ).created.body.json
        }
    }

    func edit(_ crewID: String, id: String, body: String) async throws -> CrewMessage {
        try await NorthAPI.call {
            try await api.editCrewMessage(path: .init(crewID: crewID, messageID: id), body: .json(.init(body: body))).ok.body.json
        }
    }

    func delete(_ crewID: String, id: String) async throws {
        try await NorthAPI.call { _ = try await api.deleteCrewMessage(path: .init(crewID: crewID, messageID: id)).noContent }
    }

    func react(_ crewID: String, id: String, emoji: String, on: Bool) async throws {
        if on {
            try await NorthAPI.call { _ = try await api.addCrewReaction(path: .init(crewID: crewID, messageID: id, emoji: emoji)).noContent }
        } else {
            try await NorthAPI.call {
                _ = try await api.removeCrewReaction(path: .init(crewID: crewID, messageID: id, emoji: emoji)).noContent
            }
        }
    }

    func pin(_ crewID: String, id: String, on: Bool) async throws {
        if on {
            try await NorthAPI.call { _ = try await api.pinCrewMessage(path: .init(crewID: crewID, messageID: id)).noContent }
        } else {
            try await NorthAPI.call { _ = try await api.unpinCrewMessage(path: .init(crewID: crewID, messageID: id)).noContent }
        }
    }

    func pins(_ crewID: String, channel: String) async throws -> [CrewMessage] {
        try await NorthAPI.call {
            try await api.listCrewPins(path: .init(crewID: crewID, channelID: channel)).ok.body.json.messages
        }
    }

    func markRead(_ crewID: String, channel: String, seq: Int64) async throws {
        try await NorthAPI.call {
            _ = try await api.markCrewChannelRead(path: .init(crewID: crewID, channelID: channel), body: .json(.init(seq: seq))).noContent
        }
    }

    func report(_ crewID: String, id: String, reason: String, note: String?) async throws {
        try await NorthAPI.call {
            _ = try await api.reportCrewMessage(
                path: .init(crewID: crewID, messageID: id),
                body: .json(.init(reason: reason, note: note))
            ).noContent
        }
    }

    /// A nil `mutedUntil` sends none, which clears the mute.
    func setNotify(_ crewID: String, notify: String, mutedUntil: Date?) async throws {
        try await NorthAPI.call {
            _ = try await api.setCrewNotifications(
                path: .init(crewID: crewID),
                body: .json(.init(notify: notify, mutedUntil: mutedUntil))
            ).noContent
        }
    }

    func unread() async throws -> Components.Schemas.CrewUnreadList {
        try await NorthAPI.call { try await api.listCrewUnread().ok.body.json }
    }

    func termsAccepted() async throws -> Bool {
        try await NorthAPI.call { try await api.getModerationTerms().ok.body.json.accepted }
    }

    func acceptTerms() async throws {
        try await NorthAPI.call { _ = try await api.acceptModerationTerms().noContent }
    }

    func block(_ userID: String) async throws {
        try await NorthAPI.call { _ = try await api.block(path: .init(userID: userID)).noContent }
    }

    func live(_ crewID: String) async throws -> HTTPBody {
        try await NorthAPI.call { try await api.streamCrewLive(path: .init(crewID: crewID)).ok.body.textEventStream }
    }
}
