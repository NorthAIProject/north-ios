import DeviceActivity
import SwiftUI

/// Renders today's screen time inside My Day.
///
/// Apple runs this extension in a sandbox: it can draw the number into the
/// app's view, but cannot hand it back to the app or send it anywhere. That is
/// why the server's screen time is still typed in or posted by a Shortcut —
/// this report is what makes typing it in a glance rather than a trip to
/// Settings.
@main
struct ScreenTimeReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { total in
            TotalActivityView(total: total)
        }
    }
}

extension DeviceActivityReport.Context {
    /// Shared by name with the app's `ScreenTimeReportView`.
    static let totalActivity = Self("Total Activity")
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (TimeInterval) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> TimeInterval {
        var total: TimeInterval = 0
        for await device in data {
            for await segment in device.activitySegments {
                total += segment.totalActivityDuration
            }
        }
        return total
    }
}

struct TotalActivityView: View {
    let total: TimeInterval

    var body: some View {
        let minutes = Int(total / 60)
        VStack(spacing: 2) {
            Text("\(minutes / 60)h \(minutes % 60)m")
                .font(.title2.weight(.semibold).monospacedDigit())
            Text("on this iPhone today")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
