import Foundation
import NorthAPI
import Testing
@testable import khepri

struct CheckInPresentationTests {
    @Test func tagsAreTrimmedDeduplicatedAndKeptInOrder() {
        #expect(CheckInTags.parse(" travel, #long-run ,, Travel,  ") == ["travel", "long-run"])
        #expect(CheckInTags.parse("") == [])
        #expect(CheckInTags.text(["travel", "long-run"]) == "travel, long-run")
    }

    @Test func knownSourcesHaveNamesAndTheRestAreGeneric() {
        #expect(CheckInSource.label("ios") == "iPhone")
        #expect(CheckInSource.label("siri") == "Siri")
        #expect(CheckInSource.label("mcp") == "Agent")
        #expect(CheckInSource.label("unknown") == "Elsewhere")
        #expect(CheckInSource.label("watch") == "Elsewhere", "a source added after this build still shows")
    }

    @Test func aSaveInTheSameMinuteIsNotAnEdit() {
        let filed = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(!checkIn(created: filed, updated: filed.addingTimeInterval(30)).wasEdited)
        #expect(checkIn(created: filed, updated: filed.addingTimeInterval(3600)).wasEdited)
    }

    private func checkIn(created: Date, updated: Date) -> CheckIn {
        CheckIn(id: "c1", localDate: "2026-10-09", mood: 4, energy: 3, wins: "", challenges: "", notes: "",
                updatedAt: updated, createdAt: created, source: "ios", tags: [])
    }
}

@MainActor
struct DataVersionTests {
    @Test func eachWriteMovesTheVersionOn() {
        let router = AppRouter()
        #expect(router.dataVersion == 0)
        router.dataChanged()
        router.dataChanged()
        #expect(router.dataVersion == 2)
    }
}
