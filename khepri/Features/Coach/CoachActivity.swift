import Foundation

/// What the mark in the coach's header shows. There is one piece of art; the
/// mood is the ring around it, as in Loci's Muse chat.
enum CoachMood: Equatable {
    case idle
    case listening
    case working
    case celebrating
}

/// The header's ring and status line, derived from a conversation.
///
/// `resolve` is pure so every state can be tested without a screen. The state
/// that lasts only a moment after a reply ends comes in as a `Flash` the
/// screen holds and clears on a timer.
struct CoachActivity: Equatable {
    var mood: CoachMood
    var status: String

    /// A short-lived state after a reply ends.
    enum Flash: Equatable {
        case done

        var duration: Duration { .milliseconds(1200) }
    }

    static let ready = CoachActivity(mood: .idle, status: String(localized: "Ready", comment: "Coach status shown under the coach's name"))
    static let catchingUp = CoachActivity(mood: .working, status: String(localized: "is catching up", comment: "Follows the coach's name: “Khepri is thinking”"))

    /// Precedence: loading, a reply being written, an answered question still
    /// running, a reply the app lost track of, a question for the person, a
    /// flash, the composer, a failed reply, an ended reflection, then Ready.
    static func resolve(
        phase: ConversationStore.Phase,
        hasReplyText: Bool = false,
        awaitingApproval: Bool = false,
        isDeciding: Bool = false,
        isStillThinking: Bool = false,
        replyFailed: Bool = false,
        ended: Bool = false,
        flash: Flash? = nil,
        isListening: Bool = false
    ) -> CoachActivity {
        switch phase {
        case .loading:
            return .catchingUp
        case .failed:
            return CoachActivity(mood: .idle, status: String(localized: "hit a snag", comment: "Follows the coach's name: “Khepri is thinking”"))
        case .replying:
            let status = hasReplyText
                ? String(localized: "is writing", comment: "Follows the coach's name: “Khepri is thinking”")
                : String(localized: "is thinking", comment: "Follows the coach's name: “Khepri is thinking”")
            return CoachActivity(mood: .working, status: status)
        case .ready:
            break
        }
        // Said yes: the write is running, so stop asking for the OK.
        if isDeciding { return CoachActivity(mood: .working, status: String(localized: "is on it", comment: "Follows the coach's name: “Khepri is thinking”")) }
        // The connection dropped mid-reply; the server is still writing it.
        if isStillThinking { return CoachActivity(mood: .working, status: String(localized: "is still thinking", comment: "Follows the coach's name: “Khepri is thinking”")) }
        if awaitingApproval { return CoachActivity(mood: .idle, status: String(localized: "needs your OK", comment: "Follows the coach's name: “Khepri is thinking”")) }
        if flash == .done { return CoachActivity(mood: .celebrating, status: String(localized: "is done", comment: "Follows the coach's name: “Khepri is thinking”")) }
        if isListening { return CoachActivity(mood: .listening, status: String(localized: "is listening", comment: "Follows the coach's name: “Khepri is thinking”")) }
        if replyFailed { return CoachActivity(mood: .idle, status: String(localized: "hit a snag", comment: "Follows the coach's name: “Khepri is thinking”")) }
        if ended { return CoachActivity(mood: .idle, status: String(localized: "finished this reflection", comment: "Follows the coach's name: “Khepri is thinking”")) }
        return .ready
    }

    /// The header for a conversation as the store has it now.
    static func resolve(_ store: ConversationStore, flash: Flash?, isListening: Bool) -> CoachActivity {
        let reply = store.messages.last.flatMap { $0.role == .coach && $0.isStreaming ? $0 : nil }
        return resolve(
            phase: store.phase,
            hasReplyText: !(reply?.text.isEmpty ?? true),
            awaitingApproval: store.pendingApproval != nil,
            isDeciding: store.isDeciding,
            isStillThinking: store.isAwaitingReply,
            replyFailed: store.replyError != nil,
            ended: store.ended,
            flash: flash,
            isListening: isListening
        )
    }

    /// The flash a reply earns when it ends: done, unless it failed, stopped
    /// to ask, or the person stopped it.
    static func flash(
        from old: ConversationStore.Phase,
        to new: ConversationStore.Phase,
        replyFailed: Bool,
        awaitingApproval: Bool,
        stopped: Bool
    ) -> Flash? {
        guard old == .replying, new == .ready, !replyFailed, !awaitingApproval, !stopped else { return nil }
        return .done
    }
}
