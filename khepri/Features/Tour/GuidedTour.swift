import Foundation
import Observation

/// One stop on the tour: a tab, and what to say about it.
enum TourStep: Int, CaseIterable, Identifiable {
    case today, coach, training

    var id: Int { rawValue }

    var tab: AppTab {
        switch self {
        case .today: .today
        case .coach: .coach
        case .training: .training
        }
    }

    var title: String {
        switch self {
        case .today: "Your day, at a glance"
        case .coach: "Your coach"
        case .training: "Training"
        }
    }

    var message: String {
        switch self {
        case .today: "One next step, your streak, and what moved. Pull down to refresh; the web and Telegram update the same day."
        case .coach: "Ask anything, from how to do a push-up to how your week went. Same coach as Telegram, with more room."
        case .training: "Your plan, each workout, and a reminder before it starts."
        }
    }
}

/// Where a person is on the three-step tour of the app.
///
/// Logic only: the spotlight overlay renders `current`, and nothing here
/// knows about views, so the rules are testable without a screen. Progress is
/// kept per device in `defaults`; the tour describes this app's layout, which
/// the web does not share.
@MainActor
@Observable
final class GuidedTour {
    /// The step being shown, or nil when the tour is not running.
    private(set) var current: TourStep?

    private let defaults: UserDefaults
    private static let finishedKey = "guidedTour.finished"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isFinished: Bool { defaults.bool(forKey: Self.finishedKey) }

    /// Starts the tour for someone who has not finished or skipped it.
    func startIfNeeded() {
        guard !isFinished, current == nil else { return }
        current = TourStep.allCases.first
    }

    /// Replays from the first step, e.g. from Settings → Show me around.
    func restart() async {
        defaults.removeObject(forKey: Self.finishedKey)
        current = TourStep.allCases.first
    }

    func advance() {
        guard let current else { return }
        if let next = TourStep(rawValue: current.rawValue + 1) {
            self.current = next
        } else {
            finish()
        }
    }

    /// Skipping ends the tour for good; Settings can bring it back.
    func skip() {
        finish()
    }

    /// "2 of 3"
    var progressLabel: String? {
        guard let current else { return nil }
        return "\(current.rawValue + 1) of \(TourStep.allCases.count)"
    }

    private func finish() {
        current = nil
        defaults.set(true, forKey: Self.finishedKey)
    }
}
