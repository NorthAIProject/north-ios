import Foundation
import NorthAPI
import Testing
import UserNotifications
@testable import khepri

/// A crew push: where it leads, whether it shows while the app is open, and the
/// inline Reply under it.
@MainActor
struct CrewNotificationsTests {
    private let crew = "11111111-1111-1111-1111-111111111111"
    private let channel = "22222222-2222-2222-2222-222222222222"
    private let other = "33333333-3333-3333-3333-333333333333"

    private var href: String { "/app/crews/\(crew)/c/\(channel)" }

    @Test func targetParsesHref() throws {
        let target = try #require(CrewNotifications.target(href: href))
        #expect(target.crewID == crew)
        #expect(target.channelID == channel)
        #expect(CrewNotifications.target(href: "/app/nudges/x") == nil)
        #expect(CrewNotifications.target(href: "/app/crews/\(crew)") == nil)
        #expect(CrewNotifications.target(href: "/app/crews/\(crew)/c/not-an-id") == nil)
    }

    @Test func suppressesOnlyOpenChannel() {
        #expect(!CrewNotifications.shouldPresent(href: href, open: (crew, channel)))
        #expect(CrewNotifications.shouldPresent(href: href, open: (crew, other)))
        #expect(CrewNotifications.shouldPresent(href: href, open: (other, channel)))
        #expect(CrewNotifications.shouldPresent(href: href, open: nil))
        #expect(CrewNotifications.shouldPresent(href: nil, open: (crew, channel)))
    }

    @Test func clientIDIsStable() {
        let first = CrewNotifications.clientID(for: "push-1")
        #expect(first == CrewNotifications.clientID(for: "push-1"))
        #expect(first != CrewNotifications.clientID(for: "push-2"))
        // A version 5 UUID with the RFC 4122 variant.
        let bytes = first.uuid
        #expect(bytes.6 >> 4 == 5)
        #expect(bytes.8 >> 6 == 0b10)
    }

    /// The names must match the server's push, or the Reply field disappears.
    @Test func categoryMatchesTheServer() throws {
        let category = CrewNotifications.notificationCategory
        #expect(category.identifier == "CREW_MESSAGE")
        let reply = try #require(category.actions.first as? UNTextInputNotificationAction)
        #expect(reply.identifier == "CREW_REPLY")
        // Replied to without opening the app.
        #expect(!reply.options.contains(.foreground))
    }

    @Test func replySendsToThePushedChannelOnce() async {
        let fake = FakeCrewChat()
        let grace = FakeBackgroundTasks()

        let tasks = grace.tasks
        await CrewNotifications.reply(" On my way ", href: href, notificationID: "push-1", service: fake, tasks: tasks)
        await CrewNotifications.reply("   ", href: href, notificationID: "push-2", service: fake, tasks: tasks)
        // A push about anything but a channel has nowhere to send to.
        let nudge = "/app/nudges/x"
        await CrewNotifications.reply("Hi", href: nudge, notificationID: "push-3", service: fake, tasks: tasks)

        #expect(await fake.sentTo == ["\(crew)/\(channel): On my way"])
        #expect(await fake.sentClientIDs == [CrewNotifications.clientID(for: "push-1")])
        #expect(grace.begun.count == 1)
        #expect(grace.ended.count == 1)
    }

    @Test func unreadDropsRemovedCrew() async {
        let fake = FakeCrewChat()
        await fake.setUnread(.init(
            crews: [.init(crewId: crew, unread: 3, mentions: 1), .init(crewId: other, unread: 2, mentions: 0)],
            total: 5
        ))
        let unread = CrewUnread(service: fake)

        await unread.refresh()
        #expect(unread.total == 5)
        #expect(unread.count(for: crew) == 3)

        unread.clear(crewID: crew)
        #expect(unread.total == 2)
        #expect(unread.count(for: crew) == 0)
        #expect(unread.byCrew[other]?.unread == 2)

        unread.reset()
        #expect(unread.total == 0)
        #expect(unread.byCrew.isEmpty)
    }

    @Test func unreadKeepsCountsWhenRefreshFails() async {
        let fake = FakeCrewChat()
        await fake.setUnread(.init(crews: [.init(crewId: crew, unread: 4, mentions: 0)], total: 4))
        let unread = CrewUnread(service: fake)
        await unread.refresh()

        let failing = CrewUnread(service: FakeCrewChat())
        await failing.refresh()

        #expect(unread.total == 4)
        #expect(failing.total == 0)
    }
}
