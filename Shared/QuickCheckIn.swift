import AppIntents
import Foundation
import NorthAPI
import WidgetKit

/// The two taps of a quick check-in, a mood and then an energy, filed from
/// the widget or a notification without opening the app. Both are asked for:
/// the server needs both, and a guessed one would teach the coach something
/// untrue.
enum QuickCheckIn {
    struct Choice: Identifiable, Sendable {
        let title: LocalizedStringResource
        let value: Int
        let symbol: String
        var id: Int { value }
    }

    /// Low, okay, good: 2, 3 and 4 on the 1–5 scale.
    static let moods: [Choice] = [
        Choice(title: "Low", value: 2, symbol: "cloud.rain"),
        Choice(title: "Okay", value: 3, symbol: "cloud.sun"),
        Choice(title: "Good", value: 4, symbol: "sun.max")
    ]

    /// Drained, OK, full: 2, 3 and 4 on the 1–5 scale.
    static let energies: [Choice] = [
        Choice(title: "Drained", value: 2, symbol: "battery.25percent"),
        Choice(title: "OK", value: 3, symbol: "battery.50percent"),
        Choice(title: "Full", value: 4, symbol: "battery.100percent")
    ]
}

/// The mood the first tap picked, held for the second. It lapses after ten
/// minutes, and at midnight, so a mood picked for one day is never filed for
/// the next.
struct QuickCheckInStep {
    static let lifetime: TimeInterval = 10 * 60

    var defaults: UserDefaults = .standard
    var now: @Sendable () -> Date = { Date() }
    var calendar: Calendar = .current

    private static let moodKey = "quickCheckIn.mood"
    private static let pickedKey = "quickCheckIn.picked"

    func pick(_ mood: Int) {
        defaults.set(mood, forKey: Self.moodKey)
        defaults.set(now().timeIntervalSince1970, forKey: Self.pickedKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.moodKey)
        defaults.removeObject(forKey: Self.pickedKey)
    }

    var pendingMood: Int? {
        guard let expiry, now() < expiry else { return nil }
        let mood = defaults.integer(forKey: Self.moodKey)
        return (1...5).contains(mood) ? mood : nil
    }

    /// When the pick lapses: ten minutes on, or midnight if that comes first.
    var expiry: Date? {
        let picked = defaults.double(forKey: Self.pickedKey)
        guard picked > 0 else { return nil }
        let at = Date(timeIntervalSince1970: picked)
        let lapse = at.addingTimeInterval(Self.lifetime)
        let today = calendar.startOfDay(for: at)
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: today) else { return lapse }
        return min(lapse, midnight)
    }
}

/// Files a quick check-in, but never over one already made today: a save
/// replaces every field, so two taps over a check-in written in the app would
/// wipe its notes, wins and tags.
struct QuickCheckInFiler: Sendable {
    enum Outcome: Equatable, Sendable {
        case filed(streak: Int, momentTitle: String?)
        case alreadyCheckedIn
    }

    let source: String
    var hasToday: @Sendable () async throws -> Bool
    var save: @Sendable (Components.Schemas.CheckInRequest) async throws -> Components.Schemas.SavedCheckIn

    func file(mood: Int, energy: Int) async throws -> Outcome {
        if try await hasToday() { return .alreadyCheckedIn }
        let saved = try await save(.init(mood: mood, energy: energy, source: source))
        return .filed(streak: saved.value2.streak, momentTitle: saved.value2.moment?.title)
    }

    /// The filer over the shared session, for the widget and the
    /// notification.
    static func live(source: String) throws -> QuickCheckInFiler {
        let client = try SharedAPI.requireClient()
        return QuickCheckInFiler(
            source: source,
            hasToday: {
                try await NorthAPI.call { try await client.listCheckIns().ok.body.json }.today != nil
            },
            save: { request in
                try await NorthAPI.call { try await client.saveTodayCheckIn(body: .json(request)).ok.body.json }
            }
        )
    }
}

/// The widget's first tap: holds the mood and turns the widget to energy.
struct PickCheckInMoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Pick Check-in Mood"
    static let isDiscoverable = false

    @Parameter(title: "Mood", inclusiveRange: (1, 5))
    var mood: Int

    init() {}

    init(mood: Int) {
        self.mood = mood
    }

    func perform() async throws -> some IntentResult {
        QuickCheckInStep().pick(mood)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// The widget's second tap: files the check-in with the mood held.
struct FileQuickCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "File Quick Check-in"
    static let isDiscoverable = false

    @Parameter(title: "Energy", inclusiveRange: (1, 5))
    var energy: Int

    init() {}

    init(energy: Int) {
        self.energy = energy
    }

    func perform() async throws -> some IntentResult {
        let step = QuickCheckInStep()
        defer {
            step.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
        guard let mood = step.pendingMood else { return .result() }
        _ = try await QuickCheckInFiler.live(source: "widget").file(mood: mood, energy: energy)
        return .result()
    }
}

/// Puts the widget back to the mood row.
struct CancelQuickCheckInIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel Quick Check-in"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        QuickCheckInStep().clear()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
