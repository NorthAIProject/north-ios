import AppIntents
import NorthKit
import SwiftUI
import WidgetKit

/// Home Screen: the next session, the streak, and water, with a button to log
/// a glass without opening the app.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Your next workout, your check-in streak and today's water.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let glance = entry.snapshot {
            switch family {
            case .systemMedium: TodayMediumView(glance: glance)
            default: TodaySmallView(glance: glance)
            }
        } else {
            WidgetMessage(signedIn: entry.signedIn)
        }
    }
}

struct TodaySmallView: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionLabel(session: glance.next)
            Spacer(minLength: 0)
            StreakLine(glance: glance)
            WaterBar(glance: glance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: glance.next?.isToday == true ? "khepri://training/next" : "khepri://today"))
    }
}

/// The small widget's content on the left, water and its buttons on the right.
struct TodayMediumView: View {
    let glance: Glance

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SessionLabel(session: glance.next)
                Spacer(minLength: 0)
                StreakLine(glance: glance)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 8) {
                Text("WATER")
                    .font(.caption2.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("\(glance.waterML) ml")
                    .font(.title3.weight(.light).monospacedDigit())
                    .contentTransition(.numericText())
                WaterBar(glance: glance)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(intent: LogWaterIntent(amountML: 250)) {
                        Label("250 ml", systemImage: "plus")
                    }
                    if !glance.checkedInToday {
                        Link(destination: URL(string: "khepri://check-ins")!) {
                            Image(systemName: "checkmark.circle")
                        }
                        .accessibilityLabel("Check in")
                    }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.bordered)
                .tint(NorthColor.signal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(URL(string: "khepri://today"))
    }
}

/// The next session, or a quiet note when there is no plan.
private struct SessionLabel: View {
    let session: Glance.Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.caption2.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text(session?.focus ?? "No plan yet")
                .font(.headline)
                .lineLimit(2)
        }
    }

    private var eyebrow: String {
        guard let session else { return "TRAINING" }
        let day = session.isToday ? "TODAY" : session.weekday.uppercased()
        return [day, session.startTime].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct StreakLine: View {
    let glance: Glance

    var body: some View {
        Label {
            Text(glance.streak == 1 ? "1 day" : "\(glance.streak) days")
                .monospacedDigit()
        } icon: {
            Image(systemName: glance.checkedInToday ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(glance.checkedInToday ? NorthColor.signal : .secondary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Check-in streak, \(glance.streak) days\(glance.checkedInToday ? ", done today" : "")")
    }
}

private struct WaterBar: View {
    let glance: Glance

    var body: some View {
        Gauge(value: glance.waterFraction) { EmptyView() }
            .gaugeStyle(.linearCapacity)
            .tint(NorthColor.signal)
            .accessibilityLabel("Water, \(glance.waterML) of \(glance.waterTargetML) ml")
    }
}

struct WidgetMessage: View {
    let signedIn: Bool

    var body: some View {
        Text(signedIn ? "Khepri could not be reached." : "Open Khepri to sign in.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
