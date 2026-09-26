import Foundation
import NorthAPI
import Observation

protocol DayServicing: Sendable {
    /// One local date; nil is today on the server's clock.
    func day(_ date: String?) async throws -> DayResponse
}

struct DayService: DayServicing {
    var api: Client = API.shared

    func day(_ date: String?) async throws -> DayResponse {
        try await NorthAPI.call { try await api.getDay(query: .init(date: date)).ok.body.json }
    }
}

/// My Day's state: which date is on screen and what the server said about it.
@MainActor @Observable
final class DayStore {
    private(set) var day: DayResponse?
    private(set) var error: String?
    /// nil means today, so a store left open past midnight follows the day.
    private(set) var date: Date?

    private let service: DayServicing
    private let calendar: Calendar

    init(service: DayServicing = DayService(), calendar: Calendar = .current) {
        self.service = service
        self.calendar = calendar
    }

    var isToday: Bool { day?.isToday ?? (date == nil) }

    func load() async {
        do {
            day = try await service.day(date.map(CalendarDay.string(from:)))
            error = nil
        } catch {
            // Keep what is on screen if a refresh fails.
            if day == nil { self.error = error.localizedDescription }
        }
    }

    /// Moves a day back or forward. Stepping onto today goes back to "today"
    /// rather than pinning the date.
    func step(_ days: Int) async {
        let base = date ?? calendar.startOfDay(for: .now)
        let next = calendar.date(byAdding: .day, value: days, to: base) ?? base
        date = calendar.isDateInToday(next) ? nil : next
        await load()
    }

    func goToToday() async {
        date = nil
        await load()
    }
}
