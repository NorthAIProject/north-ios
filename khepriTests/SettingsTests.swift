import Foundation
import NorthAPI
import Testing
@testable import khepri

@MainActor
struct EditableTests {
    struct Draft: Equatable { var name: String }

    @Test func tracksChangesAgainstWhatTheServerHas() async {
        let editable = Editable<Draft>()
        await editable.load { Draft(name: "Ana") }
        #expect(!editable.hasChanges)

        editable.value?.name = "Ana L."
        #expect(editable.hasChanges)

        let accepted = await editable.save { draft in Draft(name: draft.name.uppercased()) }
        #expect(accepted)
        #expect(editable.value == Draft(name: "ANA L."), "the server's version wins")
        #expect(!editable.hasChanges)
    }

    @Test func aRefusedSaveKeepsTheEditAndSaysWhy() async {
        let editable = Editable<Draft>()
        await editable.load { Draft(name: "Ana") }
        editable.value?.name = ""

        let accepted = await editable.save { _ in throw APIError.fieldValidation(message: "Name is required.", fields: [:]) }
        #expect(!accepted)
        #expect(editable.value?.name == "", "the edit is still there to fix")
        #expect(editable.error == "Name is required.")
        #expect(editable.hasChanges)
    }
}

struct ClockTimeTests {
    @Test(arguments: ["00:00", "07:05", "22:00", "23:59"])
    func roundTrips(_ time: String) {
        #expect(ClockTime.string(from: ClockTime.date(from: time)) == time)
    }
}
