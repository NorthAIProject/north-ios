import Foundation
import NorthAPI
import Testing
@testable import khepri

/// Reads back a fixed list and records what was committed.
actor StubCapture: CaptureServicing {
    let reading: CaptureReading
    private(set) var committed: [[CaptureItem]] = []

    init(_ items: [CaptureItem], unparsed: [String] = []) {
        reading = CaptureReading(items: items, unparsed: unparsed)
    }

    func parse(_ text: String) async throws -> CaptureReading { reading }

    func commit(_ items: [CaptureItem]) async throws -> CaptureOutcome {
        committed.append(items)
        return CaptureOutcome(written: items.count, failed: 0)
    }
}

@MainActor
struct CaptureDraftTests {
    private let water = CaptureItem(kind: .water, source: "500 ml")
    private let sleep = CaptureItem(kind: .sleep, source: "slept 7 hours", uncertain: true)
    private let food = CaptureItem(kind: .food, source: "a sandwich", problem: "No ingredient matched.")

    private func reviewed(_ items: [CaptureItem]) async -> (CaptureDraft, StubCapture) {
        let service = StubCapture(items)
        let draft = CaptureDraft(service: service)
        draft.text = "drank 500 ml, slept 7 hours, ate a sandwich"
        await draft.review()
        return (draft, service)
    }

    @Test func writableItemsStartChosenAndProblemsDoNot() async {
        let (draft, _) = await reviewed([water, sleep, food])
        #expect(draft.isChosen(0))
        #expect(draft.isChosen(1))
        #expect(!draft.isChosen(2))
        #expect(!draft.isWritable(2))
    }

    @Test func commitSendsOnlyChosenWritableItems() async {
        let (draft, service) = await reviewed([water, sleep, food])
        draft.setChosen(1, false)
        #expect(draft.itemsToLog == [water])

        let saved = await draft.log()
        #expect(saved)
        #expect(await service.committed == [[water]])
        #expect(draft.result == "Logged 1")
        #expect(draft.text.isEmpty)
        #expect(draft.items.isEmpty)
    }

    @Test func anItemWithAProblemIsNeverSent() async {
        let (draft, service) = await reviewed([water, food])
        draft.setChosen(1, true)
        #expect(!draft.isChosen(1))

        await draft.log()
        let sent = await service.committed.flatMap { $0 }
        #expect(!sent.contains(food))
    }

    @Test func nothingChosenLogsNothing() async {
        let (draft, service) = await reviewed([water, food])
        draft.setChosen(0, false)
        #expect(!draft.canLog)

        let saved = await draft.log()
        #expect(!saved)
        #expect(await service.committed.isEmpty)
    }

    @Test func reviewNeedsText() {
        let draft = CaptureDraft(service: StubCapture([]))
        draft.text = "   \n"
        #expect(!draft.canReview)
    }

    @Test func summaryMentionsFailures() {
        #expect(CaptureDraft.summary(.init(written: 3, failed: 0)) == "Logged 3")
        #expect(CaptureDraft.summary(.init(written: 2, failed: 1)) == "Logged 2, 1 could not be saved")
    }
}

struct TypedAmountTests {
    @Test func waterAcceptsTheBounds() {
        #expect(TypedAmount.parse("1", in: TypedAmount.waterMl) == 1)
        #expect(TypedAmount.parse("5000", in: TypedAmount.waterMl) == 5000)
        #expect(TypedAmount.parse(" 750 ", in: TypedAmount.waterMl) == 750)
    }

    @Test func waterRejectsOutsideTheBounds() {
        #expect(TypedAmount.parse("0", in: TypedAmount.waterMl) == nil)
        #expect(TypedAmount.parse("5001", in: TypedAmount.waterMl) == nil)
        #expect(TypedAmount.parse("", in: TypedAmount.waterMl) == nil)
        #expect(TypedAmount.parse("2.5", in: TypedAmount.waterMl) == nil)
    }

    @Test func caffeineBounds() {
        #expect(TypedAmount.parse("1000", in: TypedAmount.caffeineMg) == 1000)
        #expect(TypedAmount.parse("1001", in: TypedAmount.caffeineMg) == nil)
    }
}
