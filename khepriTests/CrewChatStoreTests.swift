import Foundation
import NorthAPI
import OpenAPIRuntime
import Testing
@testable import khepri

/// A server in miniature: increasing seq, `after`/`before`, clientID dedupe,
/// blocked authors hidden. Fetches and reports can be held open by a test.
actor FakeCrewChat: CrewChatServicing {
    private(set) var stored: [CrewMessage] = []
    private(set) var fetchCount = 0
    private(set) var afterCursors: [Int64?] = []
    private(set) var sentClientIDs: [UUID] = []
    /// "crew/channel: body" for each send, in order.
    private(set) var sentTo: [String] = []
    private var unreadList: Components.Schemas.CrewUnreadList?
    private(set) var termsAcceptedCalls = 0
    private(set) var markReadSeqs: [Int64] = []
    private var nextSeq: Int64 = 1
    private var byClientID: [UUID: String] = [:]
    private var blocked: Set<String> = []
    private var sendErrors: [APIError] = []
    private var holdFetch = false
    private var fetchGate: CheckedContinuation<Void, Never>?
    private var holdReport = false
    private var reportGate: CheckedContinuation<Void, Never>?
    private var reportError: APIError?
    private var pageSize = 50
    private var hidden: Set<String> = []
    private var reported: Set<String> = []

    static func person(_ id: String) -> CrewMessage.AuthorPayload {
        .init(value1: .init(id: id, name: id))
    }

    @discardableResult
    func seed(_ body: String, author: String = "other", kind: String = "text", channel: String = "ch") -> CrewMessage {
        let message = CrewMessage(
            id: UUID().uuidString, seq: nextSeq, channelId: channel, kind: kind, body: body,
            author: Self.person(author), mentionsMe: false, reactions: [], pinned: false,
            edited: false, deleted: false, createdAt: Date()
        )
        nextSeq += 1
        stored.append(message)
        return message
    }

    func setPageSize(_ count: Int) { pageSize = count }
    func failSends(_ errors: [APIError]) { sendErrors = errors }
    func holdNextFetch() { holdFetch = true }
    func hide(id: String) { hidden.insert(id) }
    func holdReports() { holdReport = true }
    func failReport(_ error: APIError) { reportError = error }

    func releaseFetch() {
        fetchGate?.resume()
        fetchGate = nil
    }

    func releaseReport() {
        holdReport = false
        reportGate?.resume()
        reportGate = nil
    }

    func edit(id: String, body: String) {
        guard let idx = stored.firstIndex(where: { $0.id == id }) else { return }
        stored[idx].body = body
        stored[idx].edited = true
    }

    func remove(id: String) {
        guard let idx = stored.firstIndex(where: { $0.id == id }) else { return }
        stored[idx].body = ""
        stored[idx].deleted = true
    }

    private func visible(in channel: String? = nil) -> [CrewMessage] {
        stored.filter {
            !blocked.contains($0.author?.value1.id ?? "") && !hidden.contains($0.id) && !reported.contains($0.id)
                && (channel == nil || $0.channelId == channel)
        }
    }

    func messages(
        _ crewID: String, channel: String, before: Int64?, after: Int64?
    ) async throws -> Components.Schemas.CrewMessagePage {
        fetchCount += 1
        afterCursors.append(after)
        // The answer is fixed before the gate, like a server reply still on the wire.
        var list = visible(in: channel)
        if holdFetch {
            holdFetch = false
            await withCheckedContinuation { fetchGate = $0 }
        }
        if let after {
            list = list.filter { ($0.seq ?? 0) > after }
            return .init(messages: Array(list.prefix(pageSize)), hasMore: list.count > pageSize)
        }
        if let before { list = list.filter { ($0.seq ?? 0) < before } }
        return .init(messages: Array(list.suffix(pageSize)), hasMore: list.count > pageSize)
    }

    func message(_ crewID: String, id: String) async throws -> CrewMessage {
        guard let msg = visible().first(where: { $0.id == id }) else { throw APIError.notFound(nil) }
        return msg
    }

    func send(
        _ crewID: String, channel: String, body: String, replyTo: String?, clientID: UUID
    ) async throws -> CrewMessage {
        sentClientIDs.append(clientID)
        sentTo.append("\(crewID)/\(channel): \(body)")
        if !sendErrors.isEmpty { throw sendErrors.removeFirst() }
        if let id = byClientID[clientID], let msg = stored.first(where: { $0.id == id }) { return msg }
        let msg = seed(body, author: "me")
        byClientID[clientID] = msg.id
        return msg
    }

    func edit(_ crewID: String, id: String, body: String) async throws -> CrewMessage {
        edit(id: id, body: body)
        return try await message(crewID, id: id)
    }

    func delete(_ crewID: String, id: String) async throws { remove(id: id) }
    func react(_ crewID: String, id: String, emoji: String, on: Bool) async throws {}
    func pin(_ crewID: String, id: String, on: Bool) async throws {}
    func pins(_ crewID: String, channel: String) async throws -> [CrewMessage] { [] }

    func markRead(_ crewID: String, channel: String, seq: Int64) async throws { markReadSeqs.append(seq) }

    func report(_ crewID: String, id: String, reason: String, note: String?) async throws {
        reported.insert(id)
        if holdReport { await withCheckedContinuation { reportGate = $0 } }
        if let reportError { throw reportError }
    }

    func setNotify(_ crewID: String, notify: String, mutedUntil: Date?) async throws {}
    func space(_ crewID: String) async throws -> CrewSpace { throw APIError.notFound(nil) }
    func setUnread(_ list: Components.Schemas.CrewUnreadList) { unreadList = list }

    func unread() async throws -> Components.Schemas.CrewUnreadList {
        guard let unreadList else { throw APIError.notFound(nil) }
        return unreadList
    }
    func termsAccepted() async throws -> Bool { true }
    func acceptTerms() async throws { termsAcceptedCalls += 1 }
    func block(_ userID: String) async throws { blocked.insert(userID) }
    func live(_ crewID: String) async throws -> HTTPBody { throw APIError.notFound(nil) }
}

@MainActor
struct CrewChatStoreTests {
    private func makeStore(_ fake: FakeCrewChat) -> CrewChatStore {
        CrewChatStore(crewID: "crew", channelID: "ch", meID: "me", service: fake)
    }

    /// Waits (bounded) until the fake has seen `count` fetches.
    private func waitForFetches(_ count: Int, _ fake: FakeCrewChat) async {
        for _ in 0..<2000 {
            if await fake.fetchCount >= count { return }
            await Task.yield()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func mergeIsUniqueAndOrdered() async throws {
        let fake = FakeCrewChat()
        for idx in 1...3 { await fake.seed("msg\(idx)") }
        let store = makeStore(fake)
        await store.load()
        await fake.seed("m4")
        await store.handle(.message(channelID: "ch", seq: 4))
        // A second signal for a message already merged must not add a row.
        await fake.seed("m5")
        await store.handle(.message(channelID: "ch", seq: 5))
        await store.handle(.message(channelID: "ch", seq: 5))
        #expect(store.rows.compactMap(\.seq) == [1, 2, 3, 4, 5])
        #expect(Set(store.rows.map(\.id)).count == 5)
    }

    @Test(.timeLimit(.minutes(1)))
    func overlappingSignalsFetchOnceMore() async throws {
        let fake = FakeCrewChat()
        await fake.seed("m1")
        let store = makeStore(fake)
        await store.load()
        let before = await fake.fetchCount
        await fake.seed("m2")
        await fake.holdNextFetch()
        let first = Task { await store.handle(.message(channelID: "ch", seq: 2)) }
        await waitForFetches(before + 1, fake)
        await fake.seed("m3")
        await store.handle(.message(channelID: "ch", seq: 3))
        await store.handle(.message(channelID: "ch", seq: 3))
        await fake.releaseFetch()
        await first.value
        #expect(await fake.fetchCount == before + 2)
        #expect(store.rows.compactMap(\.seq) == [1, 2, 3])
    }

    @Test(.timeLimit(.minutes(1)))
    func messageForAnotherChannelIsIgnored() async throws {
        let fake = FakeCrewChat()
        await fake.seed("m1")
        let store = makeStore(fake)
        await store.load()
        let before = await fake.fetchCount
        await store.handle(.message(channelID: "other", seq: 9))
        #expect(await fake.fetchCount == before)
    }

    @Test(.timeLimit(.minutes(1)))
    func updateRefetchesThatMessage() async throws {
        let fake = FakeCrewChat()
        let msg = await fake.seed("old")
        let store = makeStore(fake)
        await store.load()
        await fake.edit(id: msg.id, body: "new")
        await store.handle(.update(messageID: msg.id))
        #expect(store.rows.first?.body == "new")
        #expect(store.rows.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func foregroundResyncs() async throws {
        let fake = FakeCrewChat()
        let first = await fake.seed("a")
        let second = await fake.seed("b")
        let store = makeStore(fake)
        await store.handle(.connected)
        await fake.edit(id: first.id, body: "a2")
        await fake.remove(id: second.id)
        await fake.seed("c")
        await store.handle(.connected)
        #expect(store.rows.count == 3)
        #expect(store.rows.first?.body == "a2")
        #expect(store.rows[1].deleted == true)
        #expect(Set(store.rows.map(\.id)).count == 3)
        await store.handle(.resync)
        #expect(store.rows.count == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadOlderPrepends() async throws {
        let fake = FakeCrewChat()
        for idx in 1...5 { await fake.seed("msg\(idx)") }
        await fake.setPageSize(2)
        let store = makeStore(fake)
        await store.load()
        #expect(store.rows.compactMap(\.seq) == [4, 5])
        #expect(store.hasOlder)
        await store.loadOlder()
        #expect(store.rows.compactMap(\.seq) == [2, 3, 4, 5])
        await store.loadOlder()
        #expect(store.rows.compactMap(\.seq) == [1, 2, 3, 4, 5])
        #expect(!store.hasOlder)
    }

    @Test(.timeLimit(.minutes(1)))
    func loadKeepsPending() async throws {
        let fake = FakeCrewChat()
        await fake.failSends([.server("down")])
        let store = makeStore(fake)
        await store.send("hi")
        await store.handle(.connected)
        #expect(store.pending.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func retryReusesClientID() async throws {
        let fake = FakeCrewChat()
        await fake.failSends([.server("boom")])
        let store = makeStore(fake)
        await store.load()
        await store.send("hello")
        #expect(store.pending.count == 1)
        #expect(store.pending[0].failed)
        #expect(store.error != nil)
        let id = store.pending[0].id
        await store.retry(id)
        #expect(await fake.sentClientIDs == [id, id])
        #expect(await fake.stored.count == 1)
        #expect(store.pending.isEmpty)
        #expect(store.rows.map(\.body) == ["hello"])
    }

    @Test(.timeLimit(.minutes(1)))
    func termsRequiredOpensRules() async throws {
        let fake = FakeCrewChat()
        await fake.failSends([.refused(code: "terms_required", message: "Accept the rules")])
        let store = makeStore(fake)
        await store.send("hello")
        #expect(store.needsTerms)
        #expect(store.pending.count == 1)
        #expect(!store.pending[0].failed)
        let id = store.pending[0].id
        await store.acceptTermsAndResend()
        #expect(await fake.termsAcceptedCalls == 1)
        #expect(await fake.sentClientIDs == [id, id])
        #expect(!store.needsTerms)
        #expect(store.pending.isEmpty)
        #expect(store.rows.map(\.body) == ["hello"])
    }

    @Test(.timeLimit(.minutes(1)))
    func suspendedShowsMessage() async throws {
        let fake = FakeCrewChat()
        await fake.failSends([.refused(code: "suspended", message: "You are suspended")])
        let store = makeStore(fake)
        await store.send("hello")
        #expect(store.error == "You are suspended")
        #expect(!store.needsTerms)
        #expect(store.pending[0].failed)
    }

    @Test(.timeLimit(.minutes(1)))
    func reportHidesAtOnce() async throws {
        let fake = FakeCrewChat()
        let msg = await fake.seed("rude")
        await fake.seed("fine")
        let store = makeStore(fake)
        await store.load()
        await fake.holdReports()
        let task = Task { await store.report(msg, reason: "spam", note: nil) }
        for _ in 0..<2000 where store.rows.contains(where: { $0.id == msg.id }) { await Task.yield() }
        #expect(!store.rows.contains { $0.id == msg.id })
        await fake.releaseReport()
        await task.value
        #expect(store.rows.count == 1)
        #expect(store.error == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func failedReportPutsMessageBack() async throws {
        let fake = FakeCrewChat()
        let msg = await fake.seed("rude")
        let store = makeStore(fake)
        await store.load()
        await fake.failReport(.server("no"))
        await store.report(msg, reason: "spam", note: "x")
        #expect(store.rows.map(\.id) == [msg.id])
        #expect(store.error == "no")
    }

    @Test(.timeLimit(.minutes(1)))
    func blockReloadsChannel() async throws {
        let fake = FakeCrewChat()
        let bad = await fake.seed("rude", author: "troll")
        await fake.seed("fine", author: "friend")
        let store = makeStore(fake)
        await store.load()
        let before = await fake.fetchCount
        await store.block(authorOf: bad)
        #expect(await fake.fetchCount == before + 1)
        #expect(store.rows.map(\.body) == ["fine"])
    }

    @Test(.timeLimit(.minutes(1)))
    func removedClosesChannel() async throws {
        let fake = FakeCrewChat()
        let store = makeStore(fake)
        await store.handle(.removed(userID: "someone-else"))
        #expect(store.closedReason == nil)
        await store.handle(.removed(userID: "me"))
        #expect(store.closedReason != nil)
        let empty = makeStore(fake)
        await empty.handle(.removed(userID: ""))
        #expect(empty.closedReason != nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func unknownKindKeptAsPlaceholder() async throws {
        let fake = FakeCrewChat()
        await fake.seed("???", kind: "poll")
        let store = makeStore(fake)
        await store.load()
        #expect(store.rows.count == 1)
        #expect(store.rows[0].kind == "poll")
        let json = #"{"id":"1","seq":1,"kind":"poll","future":{"x":1}}"#
        let decoded = try JSONDecoder().decode(CrewMessage.self, from: Data(json.utf8))
        #expect(decoded.kind == "poll")
    }

    @Test(.timeLimit(.minutes(1)))
    func markReadPostsCursor() async throws {
        let fake = FakeCrewChat()
        let store = makeStore(fake)
        await store.markRead()
        #expect(await fake.markReadSeqs.isEmpty)
        await fake.seed("a")
        await fake.seed("b")
        await store.load()
        await store.markRead()
        #expect(await fake.markReadSeqs == [2])
    }

    @Test(.timeLimit(.minutes(1)))
    func replyToIsCarriedAndCleared() async throws {
        let fake = FakeCrewChat()
        let msg = await fake.seed("q")
        let store = makeStore(fake)
        await store.load()
        store.replyTo = msg
        await store.send("answer")
        #expect(store.replyTo == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func updateForAnotherChannelIsIgnored() async throws {
        let fake = FakeCrewChat()
        await fake.seed("mine")
        let foreign = await fake.seed("elsewhere", channel: "other")
        let store = makeStore(fake)
        await store.load()
        await store.handle(.update(messageID: foreign.id))
        #expect(store.rows.map(\.body) == ["mine"])
        await store.markRead()
        #expect(await fake.markReadSeqs == [1])
    }

    @Test(.timeLimit(.minutes(1)))
    func updateForHiddenMessageRemovesRow() async throws {
        let fake = FakeCrewChat()
        let msg = await fake.seed("rude")
        await fake.seed("fine")
        let store = makeStore(fake)
        await store.load()
        await fake.hide(id: msg.id)
        await store.handle(.update(messageID: msg.id))
        #expect(store.rows.map(\.body) == ["fine"])
        #expect(store.error == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func sendDuringLoadSurvivesLoad() async throws {
        let fake = FakeCrewChat()
        await fake.seed("a1")
        await fake.seed("a2")
        let store = makeStore(fake)
        await fake.holdNextFetch()
        let loading = Task { await store.load() }
        await waitForFetches(1, fake)
        await store.send("mine")
        #expect(store.rows.map(\.body) == ["mine"])
        await fake.releaseFetch()
        await loading.value
        #expect(store.rows.map(\.body) == ["a1", "a2", "mine"])
        #expect(store.pending.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func staleAfterFetchDoesNotRevertResync() async throws {
        let fake = FakeCrewChat()
        await fake.seed("a1")
        let store = makeStore(fake)
        await store.load()
        let second = await fake.seed("a2")
        await fake.holdNextFetch()
        let fetching = Task { await store.handle(.message(channelID: "ch", seq: 2)) }
        await waitForFetches(2, fake)
        await fake.remove(id: second.id)
        await store.handle(.connected)
        #expect(store.rows.last?.deleted == true)
        await fake.releaseFetch()
        await fetching.value
        #expect(store.rows.count == 2)
        #expect(store.rows.last?.deleted == true)
    }
}
