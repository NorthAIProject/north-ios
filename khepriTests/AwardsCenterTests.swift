import Foundation
import NorthAPI
import Testing

@testable import khepri

/// The celebration queue: what is waiting, what was told to the server, and
/// what is owed after a failed call.
@MainActor
struct AwardsCenterTests {
    private actor FakeAwards: AwardsServicing {
        private var unseenList: [Award]
        private(set) var marked: [String] = []
        private var failing: Set<String> = []
        private var failFetch = false
        /// When set, `unseen()` answers with the list as it was when called, but only after `release()`.
        private var held = false
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var fetchesStarted = 0

        init(unseen: [Award]) { unseenList = unseen }

        func setFailing(_ ids: Set<String>) { failing = ids }
        func setUnseen(_ list: [Award]) { unseenList = list }
        func setFailFetch(_ fail: Bool) { failFetch = fail }
        func hold() { held = true }
        func release() {
            held = false
            gate?.resume()
            gate = nil
        }

        func awards() async throws -> AwardsOverview { .init(earned: [], locked: []) }
        func unseen() async throws -> [Award] {
            if failFetch { throw URLError(.timedOut) }
            let snapshot = unseenList
            fetchesStarted += 1
            if held { await withCheckedContinuation { gate = $0 } }
            return snapshot
        }
        func markSeen(_ badgeID: String) async throws {
            if failing.contains(badgeID) { throw URLError(.notConnectedToInternet) }
            marked.append(badgeID)
            unseenList.removeAll { $0.id == badgeID }
        }
    }

    private func award(_ id: String) -> Award {
        .init(id: id, area: "training", name: id, description: "Because.", earnedAt: .now, target: 1)
    }

    /// What the cover does: each page that comes to the front is reported.
    private func show(_ center: AwardsCenter) {
        for award in center.pending { center.didShow(award.id) }
    }

    @Test func refreshFillsPending() async {
        let center = AwardsCenter(service: FakeAwards(unseen: [award("a"), award("b")]))
        await center.refresh()
        #expect(center.pending.map(\.id) == ["a", "b"])
    }

    @Test func twoRefreshesDoNotDuplicate() async {
        let center = AwardsCenter(service: FakeAwards(unseen: [award("a")]))
        await center.refresh()
        await center.refresh()
        #expect(center.pending.map(\.id) == ["a"])
    }

    @Test func dismissMarksEveryShownBadgeSeen() async {
        let fake = FakeAwards(unseen: [award("a"), award("b")])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        show(center)
        await center.dismiss()
        #expect(center.pending.isEmpty)
        #expect(await fake.marked == ["a", "b"])
    }

    @Test func aBadgeNeverOnScreenIsNotMarkedSeen() async {
        let fake = FakeAwards(unseen: [award("a")])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        center.didShow("a")
        await fake.setUnseen([award("a"), award("b")])
        await center.refresh()
        #expect(center.pending.map(\.id) == ["a", "b"])
        await center.dismiss()
        #expect(await fake.marked == ["a"])
        #expect(center.pending.map(\.id) == ["b"], "b stays queued for the next time")
    }

    @Test func aFailedMarkIsRetriedOnTheNextRefreshAndNotCelebratedTwice() async {
        let fake = FakeAwards(unseen: [award("a"), award("b")])
        await fake.setFailing(["b"])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        show(center)
        await center.dismiss()
        #expect(await fake.marked == ["a"])

        // The server still lists b as unseen, but it was already celebrated here.
        await center.refresh()
        #expect(center.pending.isEmpty)
        #expect(await fake.marked == ["a"])

        await fake.setFailing([])
        await center.refresh()
        #expect(center.pending.isEmpty)
        #expect(await fake.marked == ["a", "b"])
    }

    @Test func aBadgeEarnedWhileTheCoverIsUpJoinsIt() async {
        let fake = FakeAwards(unseen: [award("a")])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        await fake.setUnseen([award("a"), award("b")])
        await center.refresh()
        #expect(center.pending.map(\.id) == ["a", "b"])
    }

    @Test func aRefreshAnsweredBeforeADismissCannotBringTheBadgeBack() async {
        let fake = FakeAwards(unseen: [award("a")])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        show(center)

        await fake.hold()
        let stale = Task { await center.refresh() }
        while await fake.fetchesStarted < 2 { await Task.yield() }
        await center.dismiss()
        await fake.release()
        await stale.value

        #expect(center.pending.isEmpty, "the stale answer still listed a as unseen")
        #expect(await fake.marked == ["a"])
    }

    @Test func resetDiscardsARefreshStillInFlight() async {
        let fake = FakeAwards(unseen: [award("old-account")])
        let center = AwardsCenter(service: fake)
        await fake.hold()
        let inFlight = Task { await center.refresh() }
        while await fake.fetchesStarted < 1 { await Task.yield() }
        center.reset()
        await fake.release()
        await inFlight.value
        #expect(center.pending.isEmpty)
    }

    @Test func resetForgetsWhatWasQueuedForTheLastAccount() async {
        let center = AwardsCenter(service: FakeAwards(unseen: [award("a")]))
        await center.refresh()
        center.reset()
        #expect(center.pending.isEmpty)
    }

    @Test func aFailedFetchKeepsWhatWasWaiting() async {
        let fake = FakeAwards(unseen: [award("a")])
        let center = AwardsCenter(service: fake)
        await center.refresh()
        await fake.setFailFetch(true)
        await center.refresh()
        #expect(center.pending.map(\.id) == ["a"])
    }
}
