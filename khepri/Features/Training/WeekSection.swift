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
                Text("A rest week — nothing is scheduled.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(week.days, id: \.date) { session in
                NavigationLink(value: DayRoute.session(planID: session.planId, dayIndex: session.dayIndex, weekday: session.weekday)) {
                    WeekSessionRow(session: session, fromOtherPlan: session.planId != followedPlanID)
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

struct WeekSessionRow: View {
    let session: WeekSession
    let fromOtherPlan: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.weekday).font(.headline)
                    if session.completed {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .northEyebrow()
                    } else if session.isNext {
                        Text("Next")
                            .northEyebrow(NorthColor.signal)
                    }
                }
                Text(fromOtherPlan ? "\(session.focus) · \(session.planName)" : session.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let start = session.startTime {
                    Label(start, systemImage: "bell")
                        .font(.subheadline.monospacedDigit())
                        .labelStyle(.titleAndIcon)
                }
                Text("\(session.exerciseCount) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
