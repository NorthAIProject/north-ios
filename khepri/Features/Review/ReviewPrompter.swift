import Foundation

/// Decides when to ask for an App Store rating.
///
/// A success is the coach answering in the app, counted at most once per
/// calendar day, so the ask comes after replies on three different days. It
/// never comes in the first 24 hours, more than once in 120 days, or after the
/// person turned it off in Settings. iOS still decides whether the system
/// sheet actually shows; `ReviewPromptPresenter` makes the request.
///
/// Logic only, kept per device in `defaults`, with the clock injected so the
/// rules are testable without waiting days.
@MainActor
@Observable
final class ReviewPrompter {
    static let shared = ReviewPrompter()

    static let successesBeforePrompt = 3
    static let firstSessionGuard: TimeInterval = 24 * 60 * 60
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    /// Settings → "Ask me to rate Khepri". On by default.
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Self.enabledKey) }
    }

    /// Set when a success makes a prompt due; the presenter clears it.
    private(set) var isPromptDue = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private static let enabledKey = "review.enabled"
    private static let firstSeenKey = "review.firstSeenAt"
    private static let successCountKey = "review.successCount"
    private static let lastCountedDayKey = "review.lastCountedDay"
    private static let lastPromptKey = "review.lastPromptAt"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        if defaults.object(forKey: Self.firstSeenKey) == nil {
            defaults.set(now(), forKey: Self.firstSeenKey)
        }
    }

    var successCount: Int { defaults.integer(forKey: Self.successCountKey) }

    /// The coach finished a reply. Counts once per calendar day.
    func recordSuccess() {
        let today = calendar.startOfDay(for: now())
        let lastCounted = defaults.object(forKey: Self.lastCountedDayKey) as? Date
        if lastCounted.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true {
            defaults.set(today, forKey: Self.lastCountedDayKey)
            defaults.set(successCount + 1, forKey: Self.successCountKey)
        }
        isPromptDue = shouldPrompt
    }

    var shouldPrompt: Bool {
        guard isEnabled, successCount >= Self.successesBeforePrompt else { return false }
        let now = now()
        if let firstSeen = defaults.object(forKey: Self.firstSeenKey) as? Date,
           now.timeIntervalSince(firstSeen) < Self.firstSessionGuard {
            return false
        }
        if let lastPrompt = defaults.object(forKey: Self.lastPromptKey) as? Date,
           now.timeIntervalSince(lastPrompt) < Self.cooldown {
            return false
        }
        return true
    }

    /// The review was requested: start counting again from zero.
    func didPrompt() {
        defaults.set(0, forKey: Self.successCountKey)
        defaults.set(now(), forKey: Self.lastPromptKey)
        isPromptDue = false
    }

    /// The moment passed (screen left, app backgrounded): wait for the next success.
    func skipPrompt() {
        isPromptDue = false
    }
}
