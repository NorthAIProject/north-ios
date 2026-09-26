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

    static let ready = CoachActivity(mood: .idle, status: "Ready")
    static let catchingUp = CoachActivity(mood: .working, status: "is catching up")

    /// Precedence: loading, a reply being written, a question for the person,
    /// a flash, the composer, a failed reply, an ended reflection, then Ready.
    static func resolve(
        phase: ConversationStore.Phase,
        hasReplyText: Bool = false,
        awaitingApproval: Bool = false,
        replyFailed: Bool = false,
        ended: Bool = false,
        flash: Flash? = nil,
        isListening: Bool = false
    ) -> CoachActivity {
        switch phase {
        case .loading:
            return .catchingUp
        case .failed:
            return CoachActivity(mood: .idle, status: "hit a snag")
        case .replying:
            return CoachActivity(mood: .working, status: hasReplyText ? "is writing" : "is thinking")
        case .ready:
            break
        }
        if awaitingApproval { return CoachActivity(mood: .idle, status: "needs your OK") }
        if flash == .done { return CoachActivity(mood: .celebrating, status: "is done") }
        if isListening { return CoachActivity(mood: .listening, status: "is listening") }
        if replyFailed { return CoachActivity(mood: .idle, status: "hit a snag") }
        if ended { return CoachActivity(mood: .idle, status: "finished this reflection") }
        return .ready
    }

    /// The header for a conversation as the store has it now.
    static func resolve(_ store: ConversationStore, flash: Flash?, isListening: Bool) -> CoachActivity {
        let reply = store.messages.last.flatMap { $0.role == .coach && $0.isStreaming ? $0 : nil }
        return resolve(
            phase: store.phase,
            hasReplyText: !(reply?.text.isEmpty ?? true),
            awaitingApproval: store.pendingApproval != nil,
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
