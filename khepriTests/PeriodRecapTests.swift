import Foundation
import UIKit
import NorthAPI
import Testing
@testable import khepri

/// Answers with a fixed recap and records each post.
actor StubRecap: PeriodRecapServicing {
    var trainingShared: Bool
    private(set) var posts: [(RecapRange, Bool)] = []

    init(trainingShared: Bool) {
        self.trainingShared = trainingShared
    }

    func recap(_ range: RecapRange) async throws -> Recap {
        Recap(range: range.rawValue, since: "2026-10-09", until: "2026-10-15",
              totals: .init(activeDays: 3, workouts: 1, sets: 3, foodLogs: 2, checkIns: 1),
              prior: .init(activeDays: 1, workouts: 1, sets: 0, foodLogs: 0, checkIns: 0),
              checkInStreak: 4,
              days: [
                  .init(date: "2026-10-14", workouts: 0, sets: 40, foodLogs: 0, checkIns: 0),
                  .init(date: "2026-10-15", workouts: 1, sets: 0, foodLogs: 2, checkIns: 1),
              ],
              highlights: [])
    }

    func share(_ range: RecapRange, shareTraining: Bool) async throws -> RecapShared {
        posts.append((range, shareTraining))
        if shareTraining { trainingShared = true }
        return RecapShared(id: "dddddddd-dddd-dddd-dddd-dddddddddddd", trainingShared: trainingShared)
    }
}

@MainActor
struct PeriodRecapTests {
    @Test func loadsEachRangeSeparately() async {
        let store = RecapStore(service: StubRecap(trainingShared: true))
        await store.load(.week)
        #expect(store.recaps[.week]?.totals.activeDays == 3)
        #expect(store.recaps[.month] == nil)
    }

    @Test func aPostFriendsCannotSeeSaysSoAndCanBeFixed() async {
        let service = StubRecap(trainingShared: false)
        let store = RecapStore(service: service)
        await store.share(.week)
        #expect(store.post == .hidden)

        await store.share(.week, shareTraining: true)
        #expect(store.post == .posted)
        let posts = await service.posts
        #expect(posts.map(\.1) == [false, true])
    }

    @Test func daysCountAreasNotAmounts() async throws {
        let recap = try await StubRecap(trainingShared: true).recap(.week)
        // Forty sets are one area; a workout, food and a check-in are three.
        #expect(recap.days.map(\.areas) == [1, 3])
    }

    @Test func shareTextLeavesOutZeros() async throws {
        var recap = try await StubRecap(trainingShared: true).recap(.week)
        recap.totals = .init(activeDays: 2, workouts: 0, sets: 5, foodLogs: 0, checkIns: 0)
        let text = recap.shareText(.week)
        #expect(text.contains("Active days: 2") && text.contains("Sets: 5"))
        #expect(!text.contains("Workouts"))
    }

    @Test func shareCardRendersAtFeedSize() async throws {
        let recap = try await StubRecap(trainingShared: true).recap(.week)
        let image = try #require(RecapShareCard.render(recap, range: .week))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1350)
        // For a look at the card: TEST_RUNNER_RECAP_CARD_OUT=/path/card.png
        if let out = ProcessInfo.processInfo.environment["RECAP_CARD_OUT"], let png = image.pngData() {
            try png.write(to: URL(fileURLWithPath: out))
        }
    }
}
