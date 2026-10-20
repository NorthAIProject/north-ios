import Foundation
import NorthAPI
import Observation

protocol DayServicing: Sendable {
    /// One local date; nil is today on the server's clock.
    func day(_ date: String?) async throws -> DayResponse
    func trends() async throws -> DayTrends
    /// What the last `days` days of training heated, for the body figure.
    func bodyMap(days: Int) async throws -> BodyMap
    /// The figure's shape, from the latest progress check.
    func bodyShape() async throws -> BodyShape
}

struct DayService: DayServicing {
    var api: Client = API.shared

    func day(_ date: String?) async throws -> DayResponse {
        try await NorthAPI.call { try await api.getDay(query: .init(date: date)).ok.body.json }
    }

    func trends() async throws -> DayTrends {
        try await NorthAPI.call { try await api.getDayTrends().ok.body.json }
    }

    func bodyMap(days: Int) async throws -> BodyMap {
        try await NorthAPI.call { try await api.getBodyMap(query: .init(days: days)).ok.body.json }
    }

    func bodyShape() async throws -> BodyShape {
        try await NorthAPI.call { BodyShape(try await api.getBodyCurrent().ok.body.json.morph) }
    }
}

/// My Day's state: which date is on screen and what the server said about it.
@MainActor @Observable
final class DayStore {
    private(set) var day: DayResponse?
    /// The Overview's trend cards. Loaded beside the day; a failure leaves
    /// the section out rather than failing the screen.
    private(set) var trends: DayTrends?
    /// The body figure's heat. Loaded beside the day like the trends; a
    /// failure keeps the last one, or leaves the figure untrained.
    private(set) var bodyMap: BodyMap?
    /// The figure's shape. A failure keeps the last one, or the figure as
    /// modelled.
    private(set) var bodyShape: BodyShape = .modelled
    private(set) var error: String?
    /// nil means today, so a store left open past midnight follows the day.
    private(set) var date: Date?

    /// The last write's failure, shown until the next one succeeds.
    private(set) var actionError: String?

    private let service: DayServicing
    let actions: DayActing
    private let calendar: Calendar

    init(service: DayServicing = DayService(), actions: DayActing = DayActions(), calendar: Calendar = .current) {
        self.service = service
        self.actions = actions
        self.calendar = calendar
    }

    /// Counts writes that succeeded. The day reloads itself; the screen
    /// owning the store watches this to refresh what else shows the write,
    /// such as Today's water tile.
    private(set) var writes = 0

    /// Runs one write and reloads the day, so every card reflects it.
    func perform(_ action: @Sendable (DayActing) async throws -> Void) async {
        do {
            try await action(actions)
            actionError = nil
            writes += 1
        } catch {
            actionError = error.localizedDescription
        }
        await load()
    }

    var isToday: Bool { day?.isToday ?? (date == nil) }

    func load() async {
        async let loadedTrends = try? service.trends()
        async let loadedBodyMap = try? service.bodyMap(days: 7)
        async let loadedShape = try? service.bodyShape()
        do {
            day = try await service.day(date.map(CalendarDay.string(from:)))
            error = nil
        } catch {
            // Keep what is on screen if a refresh fails.
            if day == nil { self.error = error.localizedDescription }
        }
        if let fresh = await loadedTrends { trends = fresh }
        if let fresh = await loadedBodyMap { bodyMap = fresh }
        if let fresh = await loadedShape { bodyShape = fresh }
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
