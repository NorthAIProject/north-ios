import AppIntents
import NorthAPI
import WidgetKit

/// Logs a glass of water. The Today widget's button runs it in place, and
/// Shortcuts and Siri can run it too.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds water to today's total in Khepri.")

    @Parameter(title: "Amount (ml)", default: 250, inclusiveRange: (50, 2000))
    var amountML: Int

    init() {}

    init(amountML: Int) {
        self.amountML = amountML
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let client = try SharedAPI.requireClient()
        let page = try await NorthAPI.call { try await client.logWater(body: .json(.init(amountMl: amountML))).created.body.json }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Logged \(amountML) ml. \(page.water.totalMl) ml today.")
    }
}
