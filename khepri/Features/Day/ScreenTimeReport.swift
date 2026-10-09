import SwiftUI

// Compiled only once scripts/configure-screen-time-target.rb has added the
// report extension, which also sets SCREEN_TIME_REPORT. Without it the app does
// not link DeviceActivity or FamilyControls at all, so it has no Screen Time
// functionality for App Review to ask about (2.1, 1.0 build 15).
#if SCREEN_TIME_REPORT
import DeviceActivity
import FamilyControls

/// Today's screen time as Apple counts it, drawn by the KhepriScreenTimeReport
/// extension. The number never reaches the app — Apple does not allow it — so
/// this sits beside the field where it is typed in.
enum ScreenTimeAccess {
    /// Whether the report extension shipped in this build. It is added by
    /// scripts/configure-screen-time-target.rb once Apple has granted the
    /// Family Controls entitlement; until then there is nothing to show.
    static var isAvailable: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(atPath: plugins.appending(path: "KhepriScreenTimeReport.appex").path())
    }

    static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Shows Apple's Screen Time prompt for this person's own device.
    static func request() async -> Bool {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            return true
        } catch {
            return false
        }
    }
}

extension DeviceActivityReport.Context {
    /// Shared by name with the extension's report scene.
    static let totalActivity = Self("Total Activity")
}

/// The report, or a button that asks for access first.
struct ScreenTimeReportView: View {
    @State private var authorized = ScreenTimeAccess.isAuthorized

    var body: some View {
        if !ScreenTimeAccess.isAvailable {
            EmptyView()
        } else if authorized {
            DeviceActivityReport(.totalActivity, filter: DeviceActivityFilter(
                segment: .daily(during: Calendar.current.dateInterval(of: .day, for: .now) ?? DateInterval())
            ))
            .frame(height: 64)
        } else {
            Button("Show screen time from this iPhone") {
                Task { authorized = await ScreenTimeAccess.request() }
            }
        }
    }
}
#else
/// Nothing to show until the report extension ships.
struct ScreenTimeReportView: View {
    var body: some View { EmptyView() }
}
#endif
