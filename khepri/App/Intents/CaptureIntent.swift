import AppIntents
import NorthAPI
import WidgetKit

/// Quick capture by voice or text: "drank 500 ml and slept 7 hours".
///
/// Same two steps as the web page. The model's reading is read back for a
/// yes before anything is written, because a capture that skips the preview
/// writes whatever the model guessed.
struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture"
    static let description = IntentDescription("Logs water, sleep, habits, weight, check-ins or food from one sentence.")

    @Parameter(title: "What happened", requestValueDialog: "What would you like to log?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = CaptureService()
        let parsed = try await service.parse(text)
        let writable = parsed.items.filter { $0.problem == nil }
        guard !writable.isEmpty else {
            let reason = parsed.items.compactMap(\.problem).first ?? "Nothing in that could be logged."
            return .result(dialog: "\(reason)")
        }

        let preview = writable.map(\.source).joined(separator: ", ")
        try await requestConfirmation(result: .result(dialog: "Log \(preview)?"), confirmationActionName: .add)

        let result = try await service.commit(writable)
        WidgetCenter.shared.reloadAllTimelines()
        if result.failed > 0 {
            return .result(dialog: "Logged \(result.written), \(result.failed) could not be saved.")
        }
        return .result(dialog: result.written == 1 ? "Logged." : "Logged \(result.written) things.")
    }
}
