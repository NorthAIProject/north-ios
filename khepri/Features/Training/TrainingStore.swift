import Foundation
import NorthAPI
import Observation

/// The Training tab's state: the plan being followed, the week it trains, its
/// edits, and keeping the phone's workout reminders in step with both.
@MainActor
@Observable
final class TrainingStore {
    enum Phase: Equatable {
        case loading
        case empty
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var plan: PlanDetail?
    private(set) var otherPlans: [PlanSummary] = []
    /// This week as the server schedules it: which days train, and which
    /// session each has. Nil when it could not be read; the plan's own days
    /// stand in for it then.
    private(set) var week: TrainingWeek?
    /// Saved plans other than the one followed, read when a week puts one of
    /// their sessions on a day.
    private(set) var otherDetails: [String: PlanDetail] = [:]
    /// Set when an edit found the plan had changed elsewhere; the plan shown
    /// is the newest, and the person may want to redo their change.
    var notice: String?
    private(set) var isEditing = false

    let service: TrainingServicing
    private let timeZone: () -> TimeZone
    private let reschedule: @MainActor (PlanDetail?, [TrainingWeek], TimeZone) async -> Void

    init(
        service: TrainingServicing = TrainingService(),
        timeZone: @escaping () -> TimeZone = { .current },
        reschedule: @escaping @MainActor (PlanDetail?, [TrainingWeek], TimeZone) async -> Void = { plan, weeks, zone in
            await WorkoutReminders.schedule(WorkoutReminderSettings.enabled ? plan : nil, weeks: weeks, timeZone: zone)
        }
    ) {
        self.service = service
        self.timeZone = timeZone
        self.reschedule = reschedule
    }

    /// Loads the plan the person follows — the server lists it first — and
    /// this week; the other plans are listed.
    func load() async {
        do {
            let plans = try await service.plans()
            guard let followed = plans.first else {
                plan = nil
                otherPlans = []
                week = nil
                phase = .empty
                await reschedule(nil, [], timeZone())
                return
            }
            otherPlans = Array(plans.dropFirst())
            let detail = try await service.plan(followed.id)
            plan = detail
            phase = .ready
            await refreshWeek()
        } catch {
            if plan == nil { phase = .failed(error.localizedDescription) }
        }
    }

    func show(_ detail: PlanDetail) async {
        plan = detail
        phase = .ready
        await refreshWeek()
    }

    /// Every plan, the followed one first: what a week can be filled from.
    var allPlans: [PlanSummary] {
        guard let plan else { return otherPlans }
        let followed = PlanSummary(
            id: plan.id, name: plan.name, weeksTotal: plan.weeksTotal,
            days: plan.days.map { .init(weekday: $0.weekday, startTime: $0.startTime, focus: $0.focus, exerciseCount: $0.exercises.count) },
            source: .init(rawValue: plan.source.rawValue) ?? .ai, createdAt: plan.createdAt, active: true
        )
        return [followed] + otherPlans
    }

    /// The plan a week's session is read from: the followed one, or another
    /// saved plan once read.
    func detail(for planID: String) -> PlanDetail? {
        planID == plan?.id ? plan : otherDetails[planID]
    }

    /// Reads another saved plan, for a day of the week that trains one of its
    /// sessions.
    func loadDetail(_ planID: String) async {
        guard detail(for: planID) == nil else { return }
        if let found = try? await service.plan(planID) { otherDetails[planID] = found }
    }

    // MARK: The week

    /// Follows another saved plan. This week switches to its usual days,
    /// keeping what was already trained.
    func follow(_ planID: String) async {
        do {
            _ = try await service.follow(plan: planID)
            otherDetails = [:]
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    func saveWeek(_ request: WeekRequest, next: Bool) async throws {
        let saved = try await service.setWeek(request, next: next)
        if !next { week = saved }
        await refreshWeek()
    }

    func resetWeek(next: Bool) async throws {
        let reset = try await service.resetWeek(next: next)
        if !next { week = reset }
        await refreshWeek()
    }

    /// Reads this week and next, and reschedules reminders from them. An
    /// older server without weeks leaves `week` nil, and reminders follow the
    /// plan's own days as they did before.
    private func refreshWeek() async {
        let this = try? await service.week(next: false)
        let following = try? await service.week(next: true)
        week = this
        for session in (this?.days ?? []) + (following?.days ?? []) where session.planId != plan?.id {
            await loadDetail(session.planId)
        }
        await reschedule(plan, [this, following].compactMap(\.self), timeZone())
    }

    // MARK: Edits

    func setStartTime(day: Int, to time: String?) async {
        await edit { plan in try await self.service.setStartTime(plan: plan, day: day, to: time) }
    }

    func add(_ slug: String, to day: Int) async {
        await edit { plan in try await self.service.addExercise(plan: plan, day: day, slug: slug) }
    }

    func swap(day: Int, index: Int, for slug: String) async {
        await edit { plan in try await self.service.swapExercise(plan: plan, day: day, index: index, slug: slug) }
    }

    func remove(day: Int, index: Int) async {
        await edit { plan in try await self.service.removeExercise(plan: plan, day: day, index: index) }
    }

    func move(day: Int, index: Int, up: Bool) async {
        await edit { plan in try await self.service.moveExercise(plan: plan, day: day, index: index, up: up) }
    }

    func setPrescription(day: Int, index: Int, sets: Int, reps: String, restSeconds: Int) async {
        await edit { plan in
            try await self.service.setPrescription(plan: plan, day: day, index: index, sets: sets, reps: reps, restSeconds: restSeconds)
        }
    }

    /// Runs one edit against the version on screen. Every edit makes a new
    /// version; the one returned replaces what is shown, and reminders follow.
    private func edit(_ run: (String) async throws -> PlanEditResult) async {
        guard let current = plan, !isEditing else { return }
        isEditing = true
        defer { isEditing = false }
        do {
            switch try await run(current.id) {
            case .saved(let updated):
                notice = nil
                await show(updated)
            case .superseded(let newest):
                notice = "This plan changed on another device. You're looking at the latest version; try that again if it still needs doing."
                await show(newest)
            }
        } catch {
            notice = error.localizedDescription
        }
    }
}

/// Workout reminders on this iPhone: on or off, and how early.
enum WorkoutReminderSettings {
    static let enabledKey = "workoutReminders.enabled"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var leadMinutes: Int {
        get { UserDefaults.standard.object(forKey: WorkoutReminders.leadMinutesKey) as? Int ?? WorkoutReminders.defaultLeadMinutes }
        set { UserDefaults.standard.set(newValue, forKey: WorkoutReminders.leadMinutesKey) }
    }
}

extension WorkoutReminderSettings {
    /// Reschedules from the newest plan, for when a setting changes outside
    /// the Training tab.
    @MainActor
    static func apply(service: TrainingServicing = TrainingService()) async {
        await TrainingStore(service: service, timeZone: { AppTimeZone.current }).load()
    }
}
