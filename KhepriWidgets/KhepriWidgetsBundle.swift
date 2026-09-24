import SwiftUI
import WidgetKit

/// Everything Khepri shows outside the app. Phase 3 adds the workout Live
/// Activity; home and Lock Screen widgets join it in Phase 7.
@main
struct KhepriWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
