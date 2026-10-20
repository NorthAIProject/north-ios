import Foundation
import NorthAPI
import Testing
@testable import khepri

struct ProgressCheckDraftTests {
    /// Either decimal mark reads, as on the web; blank is not measured, and
    /// text that is not a number holds the save.
    @Test func readsBothDecimalMarksAndFlagsWhatIsNotANumber() {
        var draft = ProgressCheckDraft()
        draft.values = [.waist: "82,5", .hips: " 98.4 ", .chest: "", .arm: "abc"]
        #expect(draft.number(.waist) == 82.5)
        #expect(draft.number(.hips) == 98.4)
        #expect(draft.number(.chest) == nil)
        #expect(draft.invalidFields == [.arm])
        #expect(draft.hasMeasurement)
        #expect(!ProgressCheckDraft().hasMeasurement)
    }

    @Test func inputCarriesTheNumbersAndTheDate() throws {
        var draft = ProgressCheckDraft()
        draft.measuredOn = try #require(CalendarDay.date(from: "2026-10-12"))
        draft.values = [.weight: "80", .waist: "85"]
        let input = draft.input()
        #expect(input.measuredOn == "2026-10-12")
        #expect(input.weightKg == 80)
        #expect(input.waistCm == 85)
        #expect(input.hipsCm == nil)
        #expect(input.source == "manual")
        #expect(input.assistConfidence == nil)
    }

    /// An estimate fills only the empty fields and marks the check assisted;
    /// a number already typed is kept.
    @Test func estimateFillsTheEmptyFieldsAndKeepsTypedOnes() {
        var draft = ProgressCheckDraft()
        draft.values = [.hips: "100"]
        let outcome = draft.apply(
            .init(waistCm: 84.4, hipsCm: 97, chestCm: nil, confidence: "medium", notes: "Loose shirt.")
        )
        #expect(outcome == .init(confidence: "medium", notes: "Loose shirt.", filled: 1, kept: 1))
        #expect(draft.number(.waist) == 84.4)
        #expect(draft.number(.hips) == 100)
        #expect(draft.number(.chest) == nil)
        let input = draft.input()
        #expect(input.source == "assisted")
        #expect(input.assistConfidence == "medium")
        #expect(input.assistNotes == "Loose shirt.")
    }

    /// An estimate that filled nothing leaves the check manual.
    @Test func anEstimateThatFilledNothingLeavesTheCheckManual() {
        var draft = ProgressCheckDraft()
        let outcome = draft.apply(.init(confidence: "low", notes: "Too dark."))
        #expect(outcome.filled == 0 && outcome.kept == 0)
        #expect(draft.input().source == "manual")
    }
}

struct ProgressCheckHistoryTests {
    /// Each number against the check before; no change shows nothing, and a
    /// carried weight is neither a change nor a base for one.
    @Test func chipsCompareWithTheCheckBefore() {
        let older = check("a", on: "2026-10-01", weight: 81, carried: true, waist: 86, hips: 99)
        let newer = check("b", on: "2026-10-08", weight: 80.2, waist: 84.9, hips: 99)
        let chips = newer.chips(since: older)
        #expect(chips.map(\.field) == [.weight, .waist, .hips])
        #expect(chips[0].delta == nil, "the earlier weight was carried")
        #expect(chips[1].delta == -1.1)
        #expect(chips[2].delta == nil, "no change is not shown")

        let carried = check("c", on: "2026-10-15", weight: 80.2, carried: true)
        #expect(carried.chips(since: newer) == [ProgressChip(field: .weight, value: 80.2, delta: nil, carried: true)])
    }

    /// Each pose's newest photo, from whichever check has one.
    @Test func lastPhotosTakeTheNewestPerPose() {
        let list = ProgressChecks(
            checks: [
                check("new", on: "2026-10-08", photos: [.init(pose: "front", url: "https://x/new-front")]),
                check("old", on: "2026-10-01", photos: [
                    .init(pose: "front", url: "https://x/old-front"), .init(pose: "side", url: "https://x/old-side")
                ])
            ],
            schedule: .init(due: false),
            canCompare: true
        )
        #expect(list.lastPhotos[.front]?.url == "https://x/new-front")
        #expect(list.lastPhotos[.side]?.url == "https://x/old-side")
        #expect(list.lastPhotos[.back] == nil)
    }
}

@MainActor
struct ProgressCheckStoreTests {
    @Test func savingReloadsAndOlderIsTheNextCheckBack() async throws {
        let service = FakeProgressService()
        let store = ProgressCheckStore(service: service)
        await store.load()
        #expect(store.checks.map(\.id) == ["b", "a"])
        #expect(store.canEstimate)
        #expect(store.older(than: store.checks[0])?.id == "a")
        #expect(store.older(than: store.checks[1]) == nil)

        var draft = ProgressCheckDraft()
        draft.values = [.waist: "84"]
        try await store.save(draft, photos: [.front: Data([1])])
        #expect(await service.saved.map(\.waistCm) == [84])
        #expect(await service.listed == 2, "a save reloads the history")
    }

    @Test func aFailedComparisonSaysWhyAndKeepsTheList() async {
        let service = FakeProgressService()
        await service.failCompare()
        let store = ProgressCheckStore(service: service)
        await store.load()
        await store.compare()
        #expect(store.compareError != nil)
        #expect(!store.comparing)
        #expect(store.checks.count == 2)
    }
}

private actor FakeProgressService: ProgressCheckServicing {
    private(set) var saved: [ProgressCheckInput] = []
    private(set) var listed = 0
    private var compareFails = false

    func failCompare() { compareFails = true }

    func checks() async throws -> ProgressChecks {
        listed += 1
        return ProgressChecks(
            checks: [check("b", on: "2026-10-08", waist: 85), check("a", on: "2026-10-01", waist: 86)],
            schedule: .init(cadence: "weekly", nextDueOn: "2026-10-15", due: false),
            canCompare: false
        )
    }

    func assist() async throws -> ProgressAssist {
        ProgressAssist(available: true, providerLabel: "Anthropic", ownProvider: false)
    }

    func save(_ input: ProgressCheckInput, photos: ProgressPhotos) async throws -> ProgressCheck {
        saved.append(input)
        return check("c", on: input.measuredOn ?? "2026-10-15")
    }

    func estimate(_ photos: ProgressPhotos) async throws -> ProgressEstimateResult {
        ProgressEstimateResult(
            estimate: .init(confidence: "low", notes: ""), providerLabel: "Anthropic", ownProvider: false
        )
    }

    func compare() async throws -> ProgressComparison {
        if compareFails { throw APIError.server("The photos couldn't be compared right now. Try again later.") }
        throw APIError.invalidResponse
    }

    func delete(_ id: String) async throws -> ProgressChecks {
        try await checks()
    }

    func setCadence(_ cadence: String) async throws -> ProgressSchedule {
        ProgressSchedule(cadence: cadence.isEmpty ? nil : cadence, due: false)
    }
}

private func check(
    _ id: String,
    on day: String,
    weight: Double? = nil,
    carried: Bool = false,
    waist: Double? = nil,
    hips: Double? = nil,
    photos: [Components.Schemas.ProgressPhoto] = []
) -> ProgressCheck {
    ProgressCheck(
        id: id, measuredOn: day, weightKg: weight, weightCarried: carried, waistCm: waist, hipsCm: hips,
        source: "manual", complete: false, photos: photos, createdAt: .now
    )
}
