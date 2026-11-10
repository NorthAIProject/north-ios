import NorthAPI
import NorthKit
import SwiftUI

/// This week's sessions on the Training tab: which days train, what each one
/// is, and which is done or next. The server schedules the week, so a short
/// week set on the web or by the coach shows here unchanged.
struct WeekSection: View {
    let week: TrainingWeek
    let followedPlanID: String
    let edit: () -> Void

    var body: some View {
        Section {
            if week.days.isEmpty {
                Text("A rest week: nothing is scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(week.days, id: \.date) { session in
                NavigationLink(value: DayRoute.session(planID: session.planId, dayIndex: session.dayIndex, weekday: session.weekday)) {
                    TrainingSessionRow(
                        weekday: session.weekday,
                        status: session.status,
                        detail: session.planId == followedPlanID ? session.focus : "\(session.focus) · \(session.planName)",
                        startTime: session.startTime,
                        exerciseCount: session.exerciseCount
                    )
                }
            }
            Button("Change This Week", systemImage: "calendar.badge.plus", action: edit)
        } header: {
            Text("This Week")
        } footer: {
            if week.custom {
                Text("Changed from your usual week. Next week goes back to it, carrying on from where this one stops.")
            }
        }
    }
}

/// One session in a list: the weekday with its Completed or Next badge and
/// what it trains, then its reminder time and exercise count. The trailing
/// column moves under the text at accessibility sizes.
struct TrainingSessionRow: View {
    /// The server's English weekday name; shown in the reader's language.
    let weekday: String
    let status: DayStatus?
    let detail: String
    let startTime: String?
    let exerciseCount: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                heading
                facts(alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                heading
                Spacer()
                facts(alignment: .trailing)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(WeekdayName.display(weekday)).font(.headline)
                switch status {
                case .completed:
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .northEyebrow()
                case .next:
                    Text("Next", comment: "Badge on the next session to train")
                        .northEyebrow(NorthColor.signal)
                case nil:
                    EmptyView()
                }
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func facts(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if let startTime {
                Label {
                    Text(ClockTime.date(from: startTime), style: .time)
                } icon: {
                    Image(systemName: "bell")
                }
                .font(.subheadline.monospacedDigit())
                .labelStyle(.titleAndIcon)
            }
            Text("\(exerciseCount) exercises")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension WeekSession {
    var status: DayStatus? {
        if completed { return .completed }
        if isNext { return .next }
        return nil
    }
}
