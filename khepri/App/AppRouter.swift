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
    /// A day of a plan, e.g. from a workout reminder.
    case trainingDay(Int)
    /// A day of a plan with its workout started: the reminder's Start button.
    case startWorkout(Int)
    /// The plan's next session, from today: a widget or the Start Today's
    /// Workout shortcut, which cannot know the plan's day index.
    case nextWorkout(start: Bool)
    /// One of More's sections by its web name, e.g. `care`, `check-ins`.
    case section(String)
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
    /// Set when a link asks for a training day; the Training tab opens it and
    /// clears it.
    var openTrainingDay: Int?
    /// Set with `openTrainingDay` when the workout should start on arrival;
    /// the day clears it.
    var startsWorkout = false
    /// Set when a link asks for the next session; the Training tab resolves
    /// it once the plan has loaded, and clears it. True starts the workout.
    var opensNextWorkout: Bool?
    /// Set when a link asks for a More section; the More tab opens it and
    /// clears it.
    var openSection: String?

    /// More's sections, by the path the web uses for them.
    static let sections: Set<String> = [
        "goals", "check-ins", "reports", "memories", "knowledge", "nutrition", "care", "mind", "decisions",
    ]

    func open(_ destination: AppDestination) {
        switch destination {
        case .tab(let tab):
            selectedTab = tab
        case .settings:
            selectedTab = .more
            showsSettings = true
        case .trainingDay(let day):
            selectedTab = .training
            openTrainingDay = day
        case .startWorkout(let day):
            selectedTab = .training
            startsWorkout = true
            openTrainingDay = day
        case .nextWorkout(let start):
            selectedTab = .training
            opensNextWorkout = start
        case .section(let id):
            selectedTab = .more
            openSection = id
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
    ///     khepri://care            → More → Care
    ///     khepri://training/next/start → today's workout, started
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
        // khepri://training/<plan>/<day>[/start]: the plan id is
        // informational; the Training tab always shows the newest version.
        if parts.first == "training", parts.count >= 2, parts[1] == "next" {
            return .nextWorkout(start: parts.count == 3 && parts[2] == "start")
        }
        if parts.first == "training", parts.count >= 3, let day = Int(parts[2]) {
            if parts.count == 4, parts[3] == "start" { return .startWorkout(day) }
            if parts.count == 3 { return .trainingDay(day) }
        }
        return switch parts.first {
        case nil, "today": .tab(.today)
        case "chat", "coach": .tab(.coach)
        case "training", "workouts", "exercises", "activity": .tab(.training)
        case "insights", "fitness", "progress": .tab(.progress)
        case "settings": .settings
        case "more": .tab(.more)
        case let id? where sections.contains(id): .section(id)
        default: nil
        }
    }
}
