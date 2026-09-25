import AppIntents
import Foundation

/// Opens the plan's next session with the workout started.
struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Today's Workout"
    static let description = IntentDescription("Opens your next training session and starts the workout.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "khepri://training/next/start")!))
    }
}
