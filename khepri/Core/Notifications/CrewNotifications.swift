import CryptoKit
import Foundation
import os
import UserNotifications

/// A crew push: a message in one of your crews' channels.
///
/// The server sends it with this category and an `href` of
/// `/app/crews/<crew>/c/<channel>`. A tap opens that channel; the Reply field
/// under the banner answers in it without opening the app. While that channel
/// is on screen its pushes are not shown: the message is already there.
enum CrewNotifications {
    /// Must match the server's crew push (`internal/apns`), or the banner
    /// arrives without its Reply field.
    nonisolated static let category = "CREW_MESSAGE"
    nonisolated static let replyAction = "CREW_REPLY"

    /// The channel on screen right now, set by `ChannelView` on appear and
    /// cleared on disappear. Main actor only: the notification delegate reads
    /// it with a hop to the main actor.
    static var openChannel: (crewID: String, channelID: String)?

    private static let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "crew-push")

    static var notificationCategory: UNNotificationCategory {
        // Sent in the background: the point is not to have to open the app.
        let reply = UNTextInputNotificationAction(
            identifier: replyAction,
            title: String(localized: "Reply", comment: "Button under a crew message notification"),
            options: [],
            textInputButtonTitle: String(
                localized: "Send", comment: "Sends a reply typed under a crew message notification"
            ),
            textInputPlaceholder: String(
                localized: "Message", comment: "Placeholder of the reply field under a crew message notification"
            )
        )
        return UNNotificationCategory(identifier: category, actions: [reply], intentIdentifiers: [])
    }

    /// The crew and channel a push's `href` leads to, or nil when it leads
    /// anywhere else.
    nonisolated static func target(href: String) -> (crewID: String, channelID: String)? {
        guard let url = URL(string: href) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }.drop { $0 == "app" }.map { $0 }
        guard let route = AppRouter.crewRoute(parts), let channelID = route.channelID else { return nil }
        return (route.crewID, channelID)
    }

    /// False only for a push about the channel already on screen.
    nonisolated static func shouldPresent(href: String?, open: (crewID: String, channelID: String)?) -> Bool {
        guard let href, let open, let target = target(href: href) else { return true }
        return target.crewID != open.crewID.lowercased() || target.channelID != open.channelID.lowercased()
    }

    /// The reply's `clientId`: the same for every attempt at answering one
    /// notification, so a retried reply is stored once. A version 5 style
    /// UUID: the SHA-1 of a fixed namespace and the notification's id.
    nonisolated static func clientID(for notificationID: String) -> UUID {
        var hasher = Insecure.SHA1()
        hasher.update(data: withUnsafeBytes(of: namespace.uuid) { Data($0) })
        hasher.update(data: Data(notificationID.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Fixed forever: changing it would give an old notification's reply a new id.
    private nonisolated static let namespace = UUID(
        uuid: (0x6B, 0x1C, 0x2F, 0x0E, 0x3D, 0x4A, 0x4E, 0x7B, 0x9C, 0x21, 0x5A, 0x8F, 0x0D, 0x3E, 0x7B, 0x64)
    )

    /// Sends the text typed under a push to the channel it came from. Empty
    /// text, or a push that is not about a channel, sends nothing. A failure
    /// is only logged: there is nowhere to show it.
    static func reply(_ text: String, href: String, notificationID: String) async {
        await reply(text, href: href, notificationID: notificationID, service: CrewChatService(), tasks: .application)
    }

    static func reply(
        _ text: String,
        href: String,
        notificationID: String,
        service: CrewChatServicing,
        tasks: BackgroundTasks
    ) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let target = target(href: href) else { return }
        do {
            _ = try await BackgroundActivity.run("Crew reply", tasks: tasks) {
                try await service.send(
                    target.crewID, channel: target.channelID, body: body, replyTo: nil,
                    clientID: clientID(for: notificationID)
                )
            }
        } catch {
            log.error("crew push: reply not sent: \(error.localizedDescription, privacy: .public)")
        }
    }
}
