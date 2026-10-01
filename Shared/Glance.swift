import Foundation
import NorthAPI

/// What the widgets show: the check-in streak, today's water, and the plan's
/// next session, or today's once it is done.
struct Glance: Equatable, Sendable {
    struct Session: Equatable, Sendable {
        var focus: String
        var weekday: String
        /// "07:30", when the day has a set time.
        var startTime: String?
        var isToday: Bool
    }

    var streak: Int
    var checkedInToday: Bool
    var waterML: Int
    var waterTargetML: Int
    var next: Session?
    /// Today's plan day, by focus, once the server counts it finished.
    var completedSessionName: String?
    /// How long the workout that finished today's plan day took. Nil when it
    /// was done on another day or the server could not say.
    var completedDuration: TimeInterval?

    var waterFraction: Double {
        waterTargetML > 0 ? min(Double(waterML) / Double(waterTargetML), 1) : 0
    }

    /// "Upper A · 52m", or just the focus without a duration.
    var completedSummary: String? {
        guard let completedSessionName else { return nil }
        guard let completedDuration, completedDuration >= 60 else { return completedSessionName }
        let duration = Duration.seconds(completedDuration)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return "\(completedSessionName) · \(duration)"
    }

    static let placeholder = Glance(
        streak: 6, checkedInToday: false, waterML: 1250, waterTargetML: 2500,
        next: Session(focus: "Upper body", weekday: "Monday", startTime: "07:30", isToday: true)
    )

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// Reads /today and the newest plan. The plan is optional: without one
    /// the widget still has the streak and water.
    static func load(with client: Client, now: Date = .now, calendar: Calendar = .current) async throws -> Glance {
        let today = try await NorthAPI.call { try await client.getToday().ok.body.json.snapshot }
        let days = (try? await newestPlanDays(with: client)) ?? []
        let done = completedToday(in: days, now: now, calendar: calendar)
        let duration: TimeInterval? = if let done {
            await duration(ofSessionFinishing: done.weekday, with: client, now: now, calendar: calendar)
        } else {
            nil
        }
        return Glance(
            streak: today.streak,
            checkedInToday: today.checkedInToday,
            waterML: today.hydration.todayML,
            waterTargetML: today.hydration.targetML,
            next: nextSession(in: days, now: now, calendar: calendar),
            completedSessionName: done?.focus,
            completedDuration: duration
        )
    }

    /// The newest plan's days, with the server's view of this week on each.
    private static func newestPlanDays(with client: Client) async throws -> [Components.Schemas.TrainingDay] {
        let plans = try await NorthAPI.call { try await client.listPlans().ok.body.json.plans }
        guard let newest = plans.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
        return try await NorthAPI.call { try await client.getPlan(path: .init(planID: newest.id)).ok.body.json.days }
    }

    /// The day the server marks next to train.
    static func nextSession(in days: [Components.Schemas.TrainingDay], now: Date, calendar: Calendar) -> Session? {
        guard let day = days.first(where: \.isNext) else { return nil }
        return Session(focus: day.focus, weekday: day.weekday, startTime: day.startTime,
                       isToday: isWeekday(day.weekday, of: now, calendar: calendar))
    }

    /// Today's plan day, when the server counts it finished this week.
    static func completedToday(in days: [Components.Schemas.TrainingDay], now: Date, calendar: Calendar) -> Components.Schemas.TrainingDay? {
        days.first { $0.completedThisWeek && isWeekday($0.weekday, of: now, calendar: calendar) }
    }

    /// The moving time of the session, ended today, that finished `weekday`'s
    /// plan day. The session list does not say which plan day a session
    /// finished; its recap does.
    private static func duration(ofSessionFinishing weekday: String, with client: Client, now: Date, calendar: Calendar) async -> TimeInterval? {
        guard let recent = try? await NorthAPI.call({ try await client.getActivity().ok.body.json.recent }) else { return nil }
        let endedToday = recent
            .compactMap { session in session.endedAt.map { (session, $0) } }
            .filter { session, ended in session.status == .completed && calendar.isDate(ended, inSameDayAs: now) }
            .sorted { $0.1 > $1.1 }
        for (session, _) in endedToday {
            let recap = try? await NorthAPI.call {
                try await client.getWorkoutRecap(path: .init(sessionID: session.id)).ok.body.json
            }
            if let recap, recap.planWeekday?.caseInsensitiveCompare(weekday) == .orderedSame {
                return TimeInterval(recap.durationSeconds)
            }
        }
        return nil
    }

    private static func isWeekday(_ weekday: String, of date: Date, calendar: Calendar) -> Bool {
        let index = calendar.component(.weekday, from: date) - 1
        return weekday.trimmingCharacters(in: .whitespaces).lowercased() == weekdays[index]
    }
}
