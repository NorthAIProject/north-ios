import Foundation
import NorthAPI

/// What the widgets show: the check-in streak, today's water, and the plan's
/// next session.
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

    var waterFraction: Double {
        waterTargetML > 0 ? min(Double(waterML) / Double(waterTargetML), 1) : 0
    }

    static let placeholder = Glance(
        streak: 6, checkedInToday: false, waterML: 1250, waterTargetML: 2500,
        next: Session(focus: "Upper body", weekday: "Monday", startTime: "07:30", isToday: true)
    )

    /// Reads /today and the newest plan. The plan is optional: without one
    /// the widget still has the streak and water.
    static func load(with client: Client, now: Date = .now, calendar: Calendar = .current) async throws -> Glance {
        let today = try await NorthAPI.call { try await client.getToday().ok.body.json.snapshot }
        let plans = (try? await NorthAPI.call { try await client.listPlans().ok.body.json.plans }) ?? []
        let newest = plans.max { $0.createdAt < $1.createdAt }
        return Glance(
            streak: today.streak,
            checkedInToday: today.checkedInToday,
            waterML: today.hydration.todayML,
            waterTargetML: today.hydration.targetML,
            next: newest.flatMap { nextSession(in: $0.days, now: now, calendar: calendar) }
        )
    }

    /// The day of the plan that comes next by weekday, today included.
    static func nextSession(in days: [Components.Schemas.DaySummary], now: Date, calendar: Calendar) -> Session? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let today = calendar.component(.weekday, from: now)
        let ahead: (Components.Schemas.DaySummary) -> Int? = { day in
            names.firstIndex(of: day.weekday.trimmingCharacters(in: .whitespaces).lowercased())
                .map { ($0 + 1 - today + 7) % 7 }
        }
        guard let day = days.filter({ ahead($0) != nil }).min(by: { ahead($0)! < ahead($1)! }) else { return nil }
        return Session(focus: day.focus, weekday: day.weekday, startTime: day.startTime, isToday: ahead(day) == 0)
    }
}
