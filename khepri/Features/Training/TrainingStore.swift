import Foundation
import NorthAPI
import Observation

/// The Training tab's state: the plan being followed, its edits, and keeping
/// the phone's workout reminders in step with it.
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
    /// Set when an edit found the plan had changed elsewhere; the plan shown
    /// is the newest, and the person may want to redo their change.
    var notice: String?
    private(set) var isEditing = false

    let service: TrainingServicing
    private let timeZone: () -> TimeZone
    private let reschedule: @MainActor (PlanDetail?, TimeZone) async -> Void

    init(
        service: TrainingServicing = TrainingService(),
        timeZone: @escaping () -> TimeZone = { .current },
        reschedule: @escaping @MainActor (PlanDetail?, TimeZone) async -> Void = { plan, zone in
            await WorkoutReminders.schedule(WorkoutReminderSettings.enabled ? plan : nil, timeZone: zone)
        }
    ) {
        self.service = service
        self.timeZone = timeZone
        self.reschedule = reschedule
    }

    /// Loads the newest plan the person follows; the rest are listed.
    func load() async {
        do {
            let plans = try await service.plans()
            guard let newest = plans.first else {
                plan = nil
                otherPlans = []
                phase = .empty
                await reschedule(nil, timeZone())
                return
            }
            otherPlans = Array(plans.dropFirst())
            let detail = try await service.plan(newest.id)
            plan = detail
            phase = .ready
            await reschedule(detail, timeZone())
        } catch {
            if plan == nil { phase = .failed(error.localizedDescription) }
        }
    }

    func show(_ detail: PlanDetail) async {
        plan = detail
        phase = .ready
        await reschedule(detail, timeZone())
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
