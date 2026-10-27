import AppIntents
import NorthKit
import SwiftUI
import WidgetKit

/// Home Screen: today's check-in in two taps, mood then energy, filed in
/// place without opening the app.
struct CheckInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CheckIn", provider: TodayProvider()) { entry in
            CheckInWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Check-in")
        .description("Check in with two taps: mood, then energy.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CheckInWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        if let glance = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                if glance.checkedInToday {
                    CheckedInView(streak: glance.streak)
                } else if entry.pendingMood != nil {
                    HStack {
                        Text("And your energy?").font(.headline)
                        Spacer(minLength: 0)
                        Button(intent: CancelQuickCheckInIntent()) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Back to mood")
                    }
                    Spacer(minLength: 0)
                    ChoiceRow(choices: QuickCheckIn.energies) { FileQuickCheckInIntent(energy: $0) }
                } else {
                    Text("How's today?").font(.headline)
                    Spacer(minLength: 0)
                    ChoiceRow(choices: QuickCheckIn.moods) { PickCheckInMoodIntent(mood: $0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(URL(string: "khepri://check-ins"))
        } else {
            WidgetMessage(signedIn: entry.signedIn)
        }
    }
}

/// Three buttons, each running its intent in place.
private struct ChoiceRow<Intent: AppIntent>: View {
    let choices: [QuickCheckIn.Choice]
    let intent: (Int) -> Intent

    var body: some View {
        HStack(spacing: 6) {
            ForEach(choices) { choice in
                Button(intent: intent(choice.value)) {
                    VStack(spacing: 2) {
                        Image(systemName: choice.symbol)
                        Text(choice.title).font(.caption2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(NorthColor.signal)
    }
}

private struct CheckedInView: View {
    let streak: Int

    var body: some View {
        Label("Checked in", systemImage: "checkmark.circle.fill")
            .font(.headline)
            .foregroundStyle(NorthColor.signal)
        Spacer(minLength: 0)
        Label {
            (streak == 1 ? Text("1 day in a row") : Text("\(streak) days in a row"))
                .monospacedDigit()
        } icon: {
            Image(systemName: "flame.fill").foregroundStyle(NorthColor.ember)
        }
        .font(.subheadline)
    }
}
