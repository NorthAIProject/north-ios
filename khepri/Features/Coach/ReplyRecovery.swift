import Foundation
import NorthAPI
import UIKit

/// How a conversation collects a reply the app stopped hearing: how often it
/// asks the server, how many times, and whether the app is in the background
/// (where asking is pointless until the person is back).
///
/// The server keeps writing a reply, and keeps running approved tools, after
/// the app hangs up, and stores what they produce. Locking the phone or
/// switching apps mid-reply cuts the connection; the reply is then fetched
/// with the conversation rather than shown as a failure.
struct ReplyRecovery: Sendable {
    var pollInterval: Duration
    var attempts: Int
    var isInBackground: @MainActor @Sendable () -> Bool

    /// Every 2 s for about a minute. Attempts, not a deadline: time spent
    /// suspended in the background does not use them up.
    nonisolated static let standard = ReplyRecovery(
        pollInterval: .seconds(2),
        attempts: 30,
        isInBackground: { UIApplication.shared.applicationState == .background }
    )

    /// How long ago a person's last message may be for an unanswered one to
    /// mean the reply is still being written, rather than one that failed.
    static let replyInFlightWindow: TimeInterval = 10 * 60

    /// Whether a failure is the connection being cut (by suspension in the
    /// background, a lock, or a moment without signal) rather than the coach
    /// failing. A cancellation counts only when the person did not stop the
    /// reply themselves, which cancels the task reading it.
    static func isInterruption(_ error: any Error) -> Bool {
        let api = APIError(error)
        return api.isInterruption || (api.urlErrorCode == .cancelled && !Task.isCancelled)
    }

    /// The last word is the person's and recent: the server is most likely
    /// still writing the reply.
    static func replyInFlight(_ detail: ConversationDetail, now: Date = .now) -> Bool {
        guard detail.pendingApproval == nil, let last = detail.messages.last, last.role == .user else { return false }
        return now.timeIntervalSince(last.createdAt) < replyInFlightWindow
    }

    /// Whether the stored conversation still lacks what is owed. Approved
    /// tools that are still running keep their approval open on the server;
    /// otherwise a question for the person, or any last word but theirs,
    /// ends the wait.
    static func stillOwed(after detail: ConversationDetail, waitingOnTools: Bool) -> Bool {
        if detail.pendingApproval != nil { return waitingOnTools }
        return detail.messages.last?.role == .user
    }
}
