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

        init(unseen: [Award]) { unseenList = unseen }

        func setFailing(_ ids: Set<String>) { failing = ids }
        func setUnseen(_ list: [Award]) { unseenList = list }

        func awards() async throws -> AwardsOverview { .init(earned: [], locked: []) }
        func unseen() async throws -> [Award] { unseenList }
        func markSeen(_ badgeID: String) async throws {
            if failing.contains(badgeID) { throw URLError(.notConnectedToInternet) }
            marked.append(badgeID)
            unseenList.removeAll { $0.id == badgeID }
        }
    }

    private func award(_ id: String) -> Award {
        .init(id: id, area: "training", name: id, description: "Because.", earnedAt: .now, target: 1)
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
        await center.dismiss()
        #expect(center.pending.isEmpty)
        #expect(await fake.marked == ["a", "b"])
    }

    @Test func aFailedMarkIsRetriedOnTheNextRefreshAndNotCelebratedTwice() async {
        let fake = FakeAwards(unseen: [award("a"), award("b")])
        await fake.setFailing(["b"])
        let center = AwardsCenter(service: fake)
        await center.refresh()
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

    @Test func resetForgetsWhatWasQueuedForTheLastAccount() async {
        let center = AwardsCenter(service: FakeAwards(unseen: [award("a")]))
        await center.refresh()
        center.reset()
        #expect(center.pending.isEmpty)
    }

    @Test func aFailedFetchKeepsWhatWasWaiting() async {
        struct Down: AwardsServicing {
            func awards() async throws -> AwardsOverview { .init(earned: [], locked: []) }
            func unseen() async throws -> [Award] { throw URLError(.timedOut) }
            func markSeen(_ badgeID: String) async throws {}
        }
        let center = AwardsCenter(service: Down())
        await center.refresh()
        #expect(center.pending.isEmpty)
    }
}
