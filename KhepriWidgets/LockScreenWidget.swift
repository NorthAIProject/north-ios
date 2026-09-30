import NorthKit
import SwiftUI
import WidgetKit

/// Lock Screen: water as a ring, the next session with the streak, or one
/// line of both.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreen", provider: TodayProvider()) { entry in
            KhepriAccessoryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Khepri")
        .description("Water, your streak and your next workout.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct KhepriAccessoryView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let glance = entry.snapshot {
            switch family {
            case .accessoryCircular:
                WaterGauge(glance: glance)
            case .accessoryInline:
                Label(Self.inline(glance), systemImage: glance.checkedInToday ? "checkmark.circle" : "circle.dashed")
            default:
                NextUpView(glance: glance)
            }
        } else {
            Text(entry.signedIn ? "Offline" : "Sign in")
        }
    }

    static func inline(_ glance: Glance) -> String {
        let streak = "\(glance.streak)d"
        guard let next = glance.next, next.isToday else { return "\(streak) · \(glance.waterML) ml" }
        return "\(streak) · \(next.focus)"
    }
}

/// Today's water as a ring.
struct WaterGauge: View {
    let glance: Glance

    var body: some View {
        Gauge(value: glance.waterFraction) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(Int(glance.waterFraction * 100))")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Water, \(glance.waterML) of \(glance.waterTargetML) ml")
        .widgetURL(URL(string: "khepri://care"))
    }
}

/// The next session, the streak, and water as a bar.
struct NextUpView: View {
    let glance: Glance

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(glance.next?.focus ?? "No plan yet")
                .font(.headline)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .monospacedDigit()
            Gauge(value: glance.waterFraction) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .accessibilityLabel("Water, \(glance.waterML) of \(glance.waterTargetML) ml")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: glance.next?.isToday == true ? "khepri://training/next" : "khepri://today"))
    }

    /// When the session is, then the streak: "Today · 6-day streak".
    private var caption: String {
        let streak = glance.streak == 1 ? "1-day streak" : "\(glance.streak)-day streak"
        guard let next = glance.next else { return streak }
        return "\(next.isToday ? "Today" : next.weekday) · \(streak)"
    }
}

/// Lock Screen: the check-in streak in a circle, one tap from today's
/// check-in. Its own widget so it can sit beside the water ring.
struct CheckInAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CheckInAccessory", provider: TodayProvider()) { entry in
            CheckInAccessoryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Check-in")
        .description("Your streak, and today's check-in in one tap.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct CheckInAccessoryView: View {
    let entry: TodayEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let glance = entry.snapshot {
                VStack(spacing: 0) {
                    Image(systemName: glance.checkedInToday ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.caption)
                    Text("\(glance.streak)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(glance.checkedInToday
                    ? "Checked in today, \(glance.streak)-day streak"
                    : "Check in, \(glance.streak)-day streak")
            } else {
                Image(systemName: "circle.dashed")
            }
        }
        .widgetURL(URL(string: "khepri://check-ins"))
    }
}
