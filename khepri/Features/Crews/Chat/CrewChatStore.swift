import Foundation
import NorthAPI
import Observation

/// One channel of a crew's chat: its messages, the sends still in flight, and
/// everything the screen needs to react to (rules sheet, closed crew, errors).
///
/// Live events are signals, never content: the store refetches what they point
/// at, one fetch at a time, so overlapping signals can never double a row.
@Observable
final class CrewChatStore {
    struct Pending: Identifiable {
        let id: UUID
        var body: String
        var replyTo: String?
        var failed: Bool
    }

    let crewID: String
    let channelID: String
    let meID: String

    private(set) var rows: [CrewMessage] = []
    private(set) var pending: [Pending] = []
    private(set) var hasOlder = false
    private(set) var needsTerms = false
    private(set) var closedReason: String?
    private(set) var error: String?
    var replyTo: CrewMessage?

    @ObservationIgnored private let service: CrewChatServicing
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var fetchAgain = false
    /// Bumped each time `load()` applies a snapshot, so older in-flight fetches can tell they are stale.
    @ObservationIgnored private var loadGeneration = 0

    init(crewID: String, channelID: String, meID: String, service: CrewChatServicing) {
        self.crewID = crewID
        self.channelID = channelID
        self.meID = meID
        self.service = service
    }

    /// The highest `seq` seen: the `after` cursor.
    private var cursor: Int64 { rows.compactMap(\.seq).max() ?? 0 }

    // MARK: Loading

    /// Replaces the rows with the newest page and keeps the pending sends.
    func load() async {
        // Rows shown before the request are the snapshot's to keep or drop: one
        // it leaves out was hidden, or its author blocked, even if it was the newest.
        let known = Set(rows.map(\.id))
        do {
            let page = try await service.messages(crewID, channel: channelID, before: nil, after: nil)
            // Only rows that arrived (a send, a live fetch) while it was in flight survive it.
            let top = page.messages.compactMap(\.seq).max() ?? 0
            rows = rows.filter { ($0.seq ?? 0) > top && !known.contains($0.id) }
            merge(page.messages)
            loadGeneration += 1
            hasOlder = page.hasMore ?? false
        } catch {
            fail(error)
        }
    }

    func loadOlder() async {
        guard hasOlder, let oldest = rows.compactMap(\.seq).min() else { return }
        do {
            let page = try await service.messages(crewID, channel: channelID, before: oldest, after: nil)
            merge(page.messages)
            hasOlder = page.hasMore ?? false
        } catch {
            fail(error)
        }
    }

    func handle(_ event: CrewLiveEvent) async {
        switch event {
        case .connected, .resync:
            await load()
        case .message(let channel, let seq):
            guard channel == channelID, seq > cursor else { return }
            await fetchNewer()
        case .update(let messageID):
            await refetch(id: messageID)
        case .removed(let userID):
            if userID.isEmpty || userID == meID {
                closedReason = String(localized: "You're no longer in this crew")
            }
        case .channels:
            break
        }
    }

    /// One fetch after the cursor at a time. A request that arrives mid-fetch
    /// only asks for another round once the running one ends.
    private func fetchNewer() async {
        if fetching {
            fetchAgain = true
            return
        }
        fetching = true
        defer { fetching = false }
        repeat {
            fetchAgain = false
            let generation = loadGeneration
            do {
                let page = try await service.messages(crewID, channel: channelID, before: nil, after: cursor)
                if generation != loadGeneration {
                    // A resync landed meanwhile; this page may predate it. Ask again.
                    fetchAgain = true
                    continue
                }
                merge(page.messages)
            } catch {
                fail(error)
                return
            }
        } while fetchAgain
    }

    private func refetch(id: String) async {
        do {
            merge([try await service.message(crewID, id: id)])
        } catch APIError.notFound {
            // Hidden, reported or blocked for this reader: it is gone, not an error.
            rows.removeAll { $0.id == id }
        } catch {
            fail(error)
        }
    }

    // MARK: Sending

    func send(_ body: String) async {
        let item = Pending(id: UUID(), body: body, replyTo: replyTo?.id, failed: false)
        pending.append(item)
        replyTo = nil
        await attempt(item.id)
    }

    func retry(_ id: UUID) async {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].failed = false
        error = nil
        await attempt(id)
    }

    func acceptTermsAndResend() async {
        do {
            try await service.acceptTerms()
        } catch {
            fail(error)
            return
        }
        needsTerms = false
        for item in pending where !item.failed {
            await attempt(item.id)
        }
    }

    private func attempt(_ id: UUID) async {
        guard let item = pending.first(where: { $0.id == id }) else { return }
        do {
            let sent = try await service.send(
                crewID, channel: channelID, body: item.body, replyTo: item.replyTo, clientID: id
            )
            pending.removeAll { $0.id == id }
            merge([sent])
        } catch APIError.refused(let code, _) where code == "terms_required" {
            needsTerms = true
        } catch {
            if let index = pending.firstIndex(where: { $0.id == id }) { pending[index].failed = true }
            fail(error)
        }
    }

    // MARK: Message actions

    func edit(_ message: CrewMessage, body: String) async {
        do {
            merge([try await service.edit(crewID, id: message.id, body: body)])
        } catch {
            fail(error)
        }
    }

    func delete(_ message: CrewMessage) async {
        do {
            try await service.delete(crewID, id: message.id)
            await refetch(id: message.id)
        } catch {
            fail(error)
        }
    }

    func toggle(_ emoji: String, on message: CrewMessage) async {
        let mine = message.reactions?.first { $0.emoji == emoji }?.mine ?? false
        do {
            try await service.react(crewID, id: message.id, emoji: emoji, on: !mine)
            await refetch(id: message.id)
        } catch {
            fail(error)
        }
    }

    func setPinned(_ message: CrewMessage, _ on: Bool) async {
        do {
            try await service.pin(crewID, id: message.id, on: on)
            await refetch(id: message.id)
        } catch {
            fail(error)
        }
    }

    /// Hides the message at once; it comes back only if the report fails. A
    /// message not loaded here (an older pin) is not added on the way back.
    func report(_ message: CrewMessage, reason: String, note: String?) async {
        let shown = rows.contains { $0.id == message.id }
        rows.removeAll { $0.id == message.id }
        do {
            try await service.report(crewID, id: message.id, reason: reason, note: note)
        } catch {
            if shown { merge([message]) }
            fail(error)
        }
    }

    func block(authorOf message: CrewMessage) async {
        guard let author = message.author?.value1.id else { return }
        do {
            try await service.block(author)
        } catch {
            fail(error)
            return
        }
        // Gone at once; the reload then catches what else the block hides.
        rows.removeAll { $0.author?.value1.id == author }
        await load()
    }

    /// Posts the cursor. Not user-facing, so a failure is dropped.
    func markRead() async {
        let seq = cursor
        guard seq > 0 else { return }
        try? await service.markRead(crewID, channel: channelID, seq: seq)
    }

    /// The person has read the error.
    func clearError() { error = nil }

    // MARK: Helpers

    /// Replaces by id, then orders by `seq`.
    private func merge(_ incoming: [CrewMessage]) {
        var byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        // Live updates cover the whole crew; another channel's message is not ours.
        for message in incoming where message.channelId == nil || message.channelId == channelID {
            byID[message.id] = message
        }
        rows = byID.values.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
    }

    private func fail(_ error: Error) {
        self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
