import Foundation
import NorthAPI
import Testing
@testable import khepri

/// The pure rules behind a crew message row: reaction glyphs, mention
/// highlighting and which actions a reader gets.
struct CrewMessageRowTests {
    private func message(
        author: String? = "other", kind: String = "text", deleted: Bool = false, pinned: Bool = false
    ) -> CrewMessage {
        CrewMessage(
            id: "m1", seq: 1, channelId: "ch", kind: kind, body: "hi",
            author: author.map { .init(value1: .init(id: $0, name: $0)) },
            mentionsMe: false, reactions: [], pinned: pinned, edited: false, deleted: deleted, createdAt: Date()
        )
    }

    @Test func glyphForKeys() {
        let expected = ["fire": "🔥", "muscle": "💪", "clap": "👏", "heart": "❤️",
                        "laugh": "😂", "hundred": "💯", "trophy": "🏆", "eyes": "👀"]
        #expect(CrewEmoji.keys == ["fire", "muscle", "clap", "heart", "laugh", "hundred", "trophy", "eyes"])
        for (key, glyph) in expected {
            #expect(CrewEmoji.glyph(key) == glyph)
        }
        #expect(CrewEmoji.glyph("thumbsup") == nil)
    }

    @Test func mentionRunsHighlight() {
        let body = "lift with @ana and @leo"
        let runs = CrewMention.runs(in: body)
        #expect(runs.map { String(body[$0]) } == ["@ana", "@leo"])
    }

    @Test func mentionRunsSkipEmailsAndShortHandles() {
        #expect(CrewMention.runs(in: "mail ana@example.com or @al").isEmpty)
        #expect(CrewMention.runs(in: "@everyone go").count == 1)
    }

    @Test func actionsForRole() {
        let others = message(author: "other")
        let mine = message(author: "me")

        let member = CrewMessageActions.available(for: others, meID: "me", role: .member)
        #expect(!member.contains(.pin))
        #expect(!member.contains(.delete))
        #expect(member.contains(.report))
        #expect(member.contains(.block))
        #expect(!member.contains(.edit))

        let admin = CrewMessageActions.available(for: others, meID: "me", role: .admin)
        #expect(admin.contains(.pin))
        #expect(admin.contains(.delete))
        #expect(!admin.contains(.edit))

        let author = CrewMessageActions.available(for: mine, meID: "me", role: .member)
        #expect(author.contains(.edit))
        #expect(author.contains(.delete))
        #expect(!author.contains(.report))
        #expect(!author.contains(.block))

        let pinned = CrewMessageActions.available(for: message(pinned: true), meID: "me", role: .owner)
        #expect(pinned.contains(.unpin))
        #expect(!pinned.contains(.pin))
    }

    @Test func noActionsOnDeletedSystemOrUnknownMessages() {
        #expect(CrewMessageActions.available(for: message(deleted: true), meID: "me", role: .owner).isEmpty)
        let system = message(author: nil, kind: "system")
        #expect(CrewMessageActions.available(for: system, meID: "me", role: .owner).isEmpty)
        #expect(CrewMessageActions.available(for: message(kind: "poll"), meID: "me", role: .owner).isEmpty)
    }

    @Test func followsNewRowsOnlyAtBottomOrForOwnMessages() {
        #expect(CrewChannelScroll.shouldFollow(atBottom: true, lastAuthorID: "other", meID: "me"))
        #expect(!CrewChannelScroll.shouldFollow(atBottom: false, lastAuthorID: "other", meID: "me"))
        #expect(!CrewChannelScroll.shouldFollow(atBottom: false, lastAuthorID: nil, meID: "me"))
        #expect(CrewChannelScroll.shouldFollow(atBottom: false, lastAuthorID: "me", meID: "me"))
        #expect(!CrewChannelScroll.shouldFollow(atBottom: false, lastAuthorID: "", meID: ""))
    }

    @Test func atBottomWithinTolerance() {
        #expect(CrewChannelScroll.isAtBottom(visibleMaxY: 1000, contentHeight: 1000))
        #expect(CrewChannelScroll.isAtBottom(visibleMaxY: 970, contentHeight: 1000))
        #expect(!CrewChannelScroll.isAtBottom(visibleMaxY: 800, contentHeight: 1000))
        // Content shorter than the screen is always at the bottom.
        #expect(CrewChannelScroll.isAtBottom(visibleMaxY: 700, contentHeight: 300))
    }

    @Test func unknownRoleIsMember() {
        #expect(CrewRole("owner") == .owner)
        #expect(CrewRole("admin") == .admin)
        #expect(CrewRole("moderator") == .member)
        #expect(CrewRole(nil) == .member)
    }
}
