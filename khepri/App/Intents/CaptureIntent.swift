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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let parsed = try await NorthAPI.call {
            try await API.shared.parseCapture(body: .json(.init(text: text))).ok.body.json
        }
        let writable = parsed.items.filter { $0.problem == nil }
        guard !writable.isEmpty else {
            let reason = parsed.items.compactMap(\.problem).first ?? "Nothing in that could be logged."
            return .result(dialog: "\(reason)")
        }

        let preview = writable.map(\.source).joined(separator: ", ")
        try await requestConfirmation(result: .result(dialog: "Log \(preview)?"), confirmationActionName: .add)

        let result = try await NorthAPI.call {
            try await API.shared.commitCapture(body: .json(.init(items: writable))).ok.body.json
        }
        WidgetCenter.shared.reloadAllTimelines()
        if result.failed > 0 {
            return .result(dialog: "Logged \(result.written), \(result.failed) could not be saved.")
        }
        return .result(dialog: result.written == 1 ? "Logged." : "Logged \(result.written) things.")
    }
}
