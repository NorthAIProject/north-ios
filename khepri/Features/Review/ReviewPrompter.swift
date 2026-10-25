import Foundation

/// Decides when to ask for an App Store rating.
///
/// A success is the coach answering, a saved workout or a logged activity,
/// counted at most once per calendar day, so the ask comes after successes on
/// three different days and never in the first 24 hours. A milestone, such as
/// the first saved workout, asks right away, even on day one. Neither asks
/// more than once in 120 days or after the person turned it off in Settings.
/// iOS still decides whether the system sheet actually shows;
/// `ReviewPromptPresenter` makes the request.
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

    /// Set when a success or a milestone makes a prompt due; the presenter clears it.
    private(set) var isPromptDue = false

    /// A milestone is waiting to be asked about, so the count and the first
    /// day do not hold the prompt back. Lives only until the prompt is asked or skipped.
    private var hasPendingMilestone = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    private static let enabledKey = "review.enabled"
    private static let firstSeenKey = "review.firstSeenAt"
    private static let successCountKey = "review.successCount"
    private static let lastCountedDayKey = "review.lastCountedDay"
    private static let lastPromptKey = "review.lastPromptAt"
    private static let milestoneKeyPrefix = "review.milestone."

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

    /// Something went well: a coach reply, a saved workout, a logged activity.
    /// Counts once per calendar day.
    func recordSuccess() {
        let today = calendar.startOfDay(for: now())
        let lastCounted = defaults.object(forKey: Self.lastCountedDayKey) as? Date
        if lastCounted.map({ !calendar.isDate($0, inSameDayAs: today) }) ?? true {
            defaults.set(today, forKey: Self.lastCountedDayKey)
            defaults.set(successCount + 1, forKey: Self.successCountKey)
        }
        isPromptDue = shouldPrompt
    }

    /// A first-time or celebratory moment: asks without waiting for the count or
    /// the first day. Cooldown and the Settings switch still apply. With `once`,
    /// it fires at most one time per install.
    func recordMilestone(once key: String? = nil) {
        if let key {
            let seenKey = Self.milestoneKeyPrefix + key
            guard !defaults.bool(forKey: seenKey) else { return }
            defaults.set(true, forKey: seenKey)
        }
        guard isEnabled, !isCoolingDown else { return }
        hasPendingMilestone = true
        isPromptDue = true
    }

    var shouldPrompt: Bool {
        guard isEnabled, !isCoolingDown else { return false }
        if hasPendingMilestone { return true }
        guard successCount >= Self.successesBeforePrompt else { return false }
        if let firstSeen = defaults.object(forKey: Self.firstSeenKey) as? Date,
           now().timeIntervalSince(firstSeen) < Self.firstSessionGuard {
            return false
        }
        return true
    }

    private var isCoolingDown: Bool {
        guard let lastPrompt = defaults.object(forKey: Self.lastPromptKey) as? Date else { return false }
        return now().timeIntervalSince(lastPrompt) < Self.cooldown
    }

    /// The review was requested: start counting again from zero.
    func didPrompt() {
        defaults.set(0, forKey: Self.successCountKey)
        defaults.set(now(), forKey: Self.lastPromptKey)
        hasPendingMilestone = false
        isPromptDue = false
    }

    /// The moment passed (screen left, app backgrounded): wait for the next
    /// success. A milestone that was not asked about is let go too.
    func skipPrompt() {
        hasPendingMilestone = false
        isPromptDue = false
    }
}
