import Foundation
import Observation

/// The five tabs. The web's sidebar has more sections than a tab bar should
/// hold, so the rest live under More.
enum AppTab: String, CaseIterable, Hashable {
    case today, coach, training, progress, more
}

/// A place in the app something can link to: a notification, a widget, a
/// `khepri://` URL, or a web path the server sent (`/app/check-ins`).
enum AppDestination: Equatable {
    case tab(AppTab)
    case settings
}

/// Owns the selected tab and turns links into destinations.
///
/// Every way into the app goes through `open(_:)`, so a notification tap and
/// a URL land in the same place by the same rules.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    /// Set when a link asks for Settings; the More tab presents it and clears
    /// it.
    var showsSettings = false

    func open(_ destination: AppDestination) {
        switch destination {
        case .tab(let tab):
            selectedTab = tab
        case .settings:
            selectedTab = .more
            showsSettings = true
        }
    }

    /// Opens a `khepri://` URL or a web path. Returns false for links this
    /// build does not understand, so the caller can fall back to the browser.
    @discardableResult
    func open(url: URL) -> Bool {
        guard let destination = Self.destination(for: url) else { return false }
        open(destination)
        return true
    }

    /// Maps both forms onto a destination:
    ///
    ///     khepri://today           → Today tab
    ///     khepri://settings        → Settings
    ///     /app/chat/…              → Coach tab (a web path from the server)
    static func destination(for url: URL) -> AppDestination? {
        let parts: [String]
        if url.scheme == "khepri" {
            parts = ([url.host()].compactMap { $0 } + url.pathComponents).filter { $0 != "/" }
        } else if url.scheme == nil || url.host() == "kheprios.com" {
            parts = url.pathComponents.filter { $0 != "/" }.drop { $0 == "app" }.map { $0 }
        } else {
            return nil
        }
        return destination(forPath: parts)
    }

    private static func destination(forPath parts: [String]) -> AppDestination? {
        switch parts.first {
        case nil, "today": .tab(.today)
        case "chat", "coach": .tab(.coach)
        case "training", "workouts", "exercises", "activity": .tab(.training)
        case "insights", "fitness", "progress": .tab(.progress)
        case "settings": .settings
        case "goals", "check-ins", "reports", "memories", "knowledge", "nutrition", "care", "mind", "decisions", "more":
            .tab(.more)
        default: nil
        }
    }
}
