import SwiftUI
import WidgetKit

/// Everything Khepri shows outside the app: the workout Live Activity, the
/// Today widget on the Home Screen, and the Lock Screen accessories.
@main
struct KhepriWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        TodayWidget()
        LockScreenWidget()
    }
}
