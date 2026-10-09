import ActivityKit
import Foundation
import NorthKit
import os

typealias WorkoutLiveState = WorkoutActivityAttributes.ContentState

/// Shows the workout on the Lock Screen and in the Dynamic Island. A
/// protocol so the session's tests can see what it would have shown.
@MainActor
protocol WorkoutLiveActivityControlling: AnyObject {
    /// The activity on screen, kept in the workout's snapshot so a relaunch
    /// can find it again.
    var activityID: String? { get }
    func start(title: String, startedAt: Date, state: WorkoutLiveState)
    /// Takes over the activity a killed run left on screen, or starts a new
    /// one when that is gone.
    func reattach(activityID: String?, title: String, startedAt: Date, state: WorkoutLiveState)
    func update(_ state: WorkoutLiveState)
    func end(_ state: WorkoutLiveState, dismissImmediately: Bool)
}

@MainActor
final class WorkoutLiveActivityController: WorkoutLiveActivityControlling {
    /// How long an activity counts as current without an update. A workout
    /// sends one every set, so past this the system marks it stale and the
    /// widget stops counting.
    static let freshFor: TimeInterval = 30 * 60

    /// The controller of the workout running in this process. Weak, so a
    /// workout that goes away without ending leaves an orphan, not a keeper.
    private static weak var current: WorkoutLiveActivityController?

    private var activity: Activity<WorkoutActivityAttributes>?
    private let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "live-activity")

    /// Ends every workout activity no workout in this process is driving:
    /// one left from a run the app was killed during, or a workout stopped
    /// on the web or in Telegram. Safe to call on every launch and return
    /// to the foreground. The activity of a workout waiting to be resumed
    /// from its snapshot is kept for it to re-attach to.
    static func endOrphans() {
        endAll(except: current?.activity?.id ?? WorkoutSnapshotStore().load()?.liveActivityID)
    }

    var activityID: String? { activity?.id }

    func start(title: String, startedAt: Date, state: WorkoutLiveState) {
        // Switched off in Settings: the workout goes on without it.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One left over from a workout the app was quit during.
        Self.endAll(except: nil)
        do {
            activity = try Activity.request(
                attributes: WorkoutActivityAttributes(title: title, startedAt: startedAt),
                content: Self.content(state)
            )
            Self.current = self
        } catch {
            log.error("live activity did not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reattach(activityID: String?, title: String, startedAt: Date, state: WorkoutLiveState) {
        let running = Activity<WorkoutActivityAttributes>.activities.first {
            $0.id == activityID && ($0.activityState == .active || $0.activityState == .stale)
        }
        guard let running else {
            start(title: title, startedAt: startedAt, state: state)
            return
        }
        activity = running
        Self.current = self
        Self.endAll(except: running.id)
        update(state)
    }

    func update(_ state: WorkoutLiveState) {
        guard let activity else { return }
        let content = Self.content(state)
        Task { await activity.update(content) }
    }

    func end(_ state: WorkoutLiveState, dismissImmediately: Bool) {
        let active = activity
        self.activity = nil
        let policy: ActivityUIDismissalPolicy = dismissImmediately ? .immediate : .default
        let content = ActivityContent(state: state, staleDate: nil)
        Task {
            if let active {
                await active.end(content, dismissalPolicy: policy)
            }
            for remaining in Activity<WorkoutActivityAttributes>.activities where remaining.id != active?.id {
                await remaining.end(content, dismissalPolicy: policy)
            }
        }
    }

    private static func content(_ state: WorkoutLiveState) -> ActivityContent<WorkoutLiveState> {
        ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(freshFor))
    }

    /// Ends each workout activity but `kept` on its last state, marked
    /// finished. The real moving time is unknown here, so it shows "Done".
    private static func endAll(except kept: Activity<WorkoutActivityAttributes>.ID?) {
        for leftover in Activity<WorkoutActivityAttributes>.activities where leftover.id != kept {
            var state = leftover.content.state
            state.phase = .finished
            state.restEndsAt = nil
            state.finalDuration = nil
            let content = ActivityContent(state: state, staleDate: nil)
            Task { await leftover.end(content, dismissalPolicy: .immediate) }
        }
    }
}
