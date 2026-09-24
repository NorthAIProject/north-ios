import ActivityKit
import Foundation
import NorthKit
import os

typealias WorkoutLiveState = WorkoutActivityAttributes.ContentState

/// Shows the workout on the Lock Screen and in the Dynamic Island. A
/// protocol so the session's tests can see what it would have shown.
@MainActor
protocol WorkoutLiveActivityControlling: AnyObject {
    func start(title: String, startedAt: Date, state: WorkoutLiveState)
    func update(_ state: WorkoutLiveState)
    func end(_ state: WorkoutLiveState, dismissImmediately: Bool)
}

@MainActor
final class WorkoutLiveActivityController: WorkoutLiveActivityControlling {
    private var activity: Activity<WorkoutActivityAttributes>?
    private let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "live-activity")

    func start(title: String, startedAt: Date, state: WorkoutLiveState) {
        // Switched off in Settings: the workout goes on without it.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One left over from a workout the app was quit during.
        for stale in Activity<WorkoutActivityAttributes>.activities {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            activity = try Activity.request(
                attributes: WorkoutActivityAttributes(title: title, startedAt: startedAt),
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            log.error("live activity did not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(_ state: WorkoutLiveState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end(_ state: WorkoutLiveState, dismissImmediately: Bool) {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: dismissImmediately ? .immediate : .default) }
    }
}
