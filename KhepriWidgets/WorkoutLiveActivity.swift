import ActivityKit
import NorthKit
import SwiftUI
import WidgetKit

/// The workout on the Lock Screen and in the Dynamic Island: the exercise and
/// set, and a rest countdown the system runs by itself.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(title: context.attributes.title, state: context.state)
                .activityBackgroundTint(nil)
                .widgetURL(URL(string: "khepri://training"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(context.state.setNumber)/\(context.state.totalSets)")
                            .font(.headline.monospacedDigit())
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                    .foregroundStyle(NorthColor.signal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state)
                        .font(.headline.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.exerciseName)
                        .font(.subheadline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .resting ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(NorthColor.signal)
            } compactTrailing: {
                Countdown(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(NorthColor.signal)
            }
            .widgetURL(URL(string: "khepri://training"))
        }
    }
}

private struct LockScreenView: View {
    let title: String
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.caption.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(state.exerciseName)
                    .font(.headline)
                    .lineLimit(1)
                Text("Set \(state.setNumber) of \(state.totalSets) · exercise \(state.exerciseNumber) of \(state.totalExercises)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(state.phase == .resting ? NorthColor.signal : .secondary)
                Countdown(state: state)
                    .font(.title2.weight(.light).monospacedDigit())
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
    }

    private var label: String {
        switch state.phase {
        case .working: "Working"
        case .resting: "Rest"
        case .paused: "Paused"
        }
    }
}

/// Rest counts down to its end; otherwise moving time counts up. Both are
/// timer text the system updates without the app running.
private struct Countdown: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.phase == .resting, let end = state.restEndsAt, end > .now {
            Text(timerInterval: Date.now...end, countsDown: true)
        } else if state.phase == .paused {
            Text("Paused")
        } else {
            Text(state.movingSince, style: .timer)
        }
    }
}
