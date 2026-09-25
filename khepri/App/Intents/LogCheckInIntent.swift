import AppIntents
import NorthAPI
import WidgetKit

/// Files today's check-in from Siri or Shortcuts, as the Check-ins screen does.
struct LogCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Check-In"
    static let description = IntentDescription("Files today's check-in with your mood and energy.")

    @Parameter(title: "Mood", description: "1 is low, 5 is great.", inclusiveRange: (1, 5))
    var mood: Int

    @Parameter(title: "Energy", description: "1 is drained, 5 is full.", inclusiveRange: (1, 5))
    var energy: Int

    @Parameter(title: "Note")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Check in with mood \(\.$mood) and energy \(\.$energy)") {
            \.$note
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let body = Components.Schemas.CheckInRequest(mood: mood, energy: energy, notes: note)
        _ = try await NorthAPI.call { try await API.shared.saveTodayCheckIn(body: .json(body)).ok.body.json }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Checked in for today.")
    }
}
