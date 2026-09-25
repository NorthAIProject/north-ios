import AppIntents

/// The phrases Siri and Spotlight offer without any setup.
struct KhepriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: ["Capture in \(.applicationName)", "Log something in \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: LogCheckInIntent(),
            phrases: ["Check in with \(.applicationName)", "Log my check-in in \(.applicationName)"],
            shortTitle: "Check In",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: ["Start today's workout in \(.applicationName)", "Start my \(.applicationName) workout"],
            shortTitle: "Start Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: LogWaterIntent(),
            phrases: ["Log water in \(.applicationName)"],
            shortTitle: "Log Water",
            systemImageName: "drop"
        )
    }
}
