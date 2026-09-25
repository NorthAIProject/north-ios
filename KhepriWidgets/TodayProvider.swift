import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    /// Nil when nobody is signed in, or the server could not be reached and
    /// there was nothing earlier to show.
    let snapshot: Glance?
    let signedIn: Bool
}

/// One provider for every Khepri widget: they all show the same day.
///
/// Refreshes every thirty minutes, and at once whenever the app or a widget
/// button changes something (`WidgetCenter.reloadAllTimelines`).
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task {
            let entry = await entry()
            let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date) ?? entry.date
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func entry() async -> TodayEntry {
        guard let client = SharedAPI.client() else {
            return TodayEntry(date: .now, snapshot: nil, signedIn: false)
        }
        let snapshot = try? await Glance.load(with: client)
        return TodayEntry(date: .now, snapshot: snapshot, signedIn: true)
    }
}
