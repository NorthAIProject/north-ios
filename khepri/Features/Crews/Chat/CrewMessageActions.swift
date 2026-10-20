import Foundation
import NorthAPI

/// The crew reactions: server keys, in the server's order, and their glyphs.
/// A key not listed here is skipped, so a new reaction never breaks a row.
nonisolated enum CrewEmoji {
    static let keys = ["fire", "muscle", "clap", "heart", "laugh", "hundred", "trophy", "eyes"]

    private static let glyphs: [String: String] = [
        "fire": "🔥", "muscle": "💪", "clap": "👏", "heart": "❤️",
        "laugh": "😂", "hundred": "💯", "trophy": "🏆", "eyes": "👀",
    ]

    static func glyph(_ key: String) -> String? { glyphs[key] }
}

/// A reader's role in a crew. Any value the server adds later reads as member.
nonisolated enum CrewRole: Equatable {
    case owner, admin, member

    init(_ raw: String?) {
        switch raw {
        case "owner": self = .owner
        case "admin": self = .admin
        default: self = .member
        }
    }

    /// Pins anything and deletes anyone's message.
    var canManage: Bool { self != .member }
}

/// `@handle` runs in a message body, found the way the server finds them: the
/// `@` starts a word (so an email address is not one) and the handle is 3 to
/// 20 letters, digits or underscores.
nonisolated enum CrewMention {
    /// The server's `(?:^|[^\w@])@(\w{3,20})\b`, as a lookbehind so the match is only the run.
    private static let pattern = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_@])@[A-Za-z0-9_]{3,20}\\b")

    static func runs(in body: String) -> [Range<String.Index>] {
        let matches = pattern?.matches(in: body, range: NSRange(body.startIndex..., in: body)) ?? []
        return matches.compactMap { Range($0.range, in: body) }
    }
}

/// What the message menu offers.
nonisolated enum CrewMessageAction: Hashable {
    case react, reply, copy, edit, delete, pin, unpin, report, block
}

nonisolated enum CrewMessageActions {
    /// The web's rules: the author edits and deletes; the owner and admins pin
    /// and delete anyone's; everybody else's message can be reported and its
    /// author blocked. Deleted, system and unknown kinds get no menu.
    static func available(for message: CrewMessage, meID: String, role: CrewRole) -> [CrewMessageAction] {
        guard message.kind == "text", message.deleted != true else { return [] }
        let authorID = message.author?.value1.id
        let mine = authorID != nil && authorID == meID
        var actions: [CrewMessageAction] = [.react]
        if authorID != nil { actions.append(.reply) }
        actions.append(.copy)
        if mine { actions.append(.edit) }
        if role.canManage { actions.append(message.pinned == true ? .unpin : .pin) }
        if mine || role.canManage { actions.append(.delete) }
        if !mine, authorID != nil {
            actions.append(.report)
            actions.append(.block)
        }
        return actions
    }
}
