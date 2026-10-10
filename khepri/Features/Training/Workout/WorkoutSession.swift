import Foundation
import NorthAPI
import NorthKit
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One training day, done: set by set, with rest between, timed on the
/// server so the web, the coach and calorie totals see it.
///
/// The workout never waits on the network. It runs here from the first tap;
/// the server session is joined as soon as it answers, and when the server
/// refuses (no body weight yet, say) the workout goes on and the finish says
/// why it was not recorded.
///
/// Nor does it depend on the app staying alive: every change is written to a
/// snapshot, and a relaunch resumes from it (`init(restoring:)`).
@MainActor
@Observable
final class WorkoutSession {
    enum Phase: Equatable {
        case ready
        case working
        case resting(until: Date)
        case finished
    }

    /// The activity the server times a gym session as.
    static let activityCode = "strength_training"

    let title: String
    let exercises: [DayExercise]
    /// The plan day this workout is for; finishing it completes that day.
    let planWeekday: String

    private(set) var phase: Phase = .ready
    private(set) var isPaused = false
    private(set) var exerciseIndex = 0
    /// 1-based, as shown.
    private(set) var setNumber = 1
    private(set) var completedSets = 0
    private(set) var startedAt: Date?
    /// The server's session; nil until it answers, and for good if it refused.
    private(set) var recorded: ActivitySession?
    /// Why the workout is not being recorded, or anything else worth saying.
    private(set) var notice: String?

    /// Every set done with a weight, in order. What the summary adds up and
    /// what the next set's prefill comes from.
    private(set) var logged: [LoggedSet] = []
    /// The last workout's sets per exercise key, loaded at the start.
    private(set) var lastTime: [String: [LiftSet]] = [:]
    /// Sets the server did not take. Kept on the phone for the summary.
    var unsavedSets: Int { logged.count(where: { $0.upload == .failed }) }

    private(set) var pausedAt: Date?
    private(set) var pausedTotal: TimeInterval = 0
    /// Rest left when paused mid-rest, restored on resume.
    private(set) var restRemaining: TimeInterval?
    private var connecting: Task<Void, Never>?
    /// Sets on their way to the server; tests wait on them.
    private(set) var saving: [Task<Void, Never>] = []
    /// Sets being sent right now, so one is never sent twice at once.
    private var uploading: Set<UUID> = []
    /// Tries so far for each set the server has not taken.
    private var attempts: [UUID: Int] = [:]
    /// The next automatic try for failed sets, while one is waiting.
    private(set) var retrying: Task<Void, Never>?
    /// How long to wait before the next try; tests make it instant.
    private let sleep: @Sendable (Duration) async -> Void
    /// After this many tries a set waits for the app to come back or the
    /// workout to finish rather than trying on its own.
    static let maxAutomaticAttempts = 8
    /// Last time's numbers arriving; tests wait on it.
    private(set) var loadingLastTime: Task<Void, Never>?
    /// Set by `init(restoring:)`: `start()` then picks the workout up where
    /// the snapshot left it instead of starting it.
    private var isRestored = false
    /// The Live Activity a restored workout re-attaches to.
    private(set) var restoredActivityID: String?

    private let service: ActivityServicing
    private let live: WorkoutLiveActivityControlling
    /// Saves the finished workout to Apple Health, when allowed.
    private let health: HealthWorkoutWriting?
    /// Where each set's weight and reps go; nil keeps them on the phone.
    private let lifts: LiftServicing?
    /// Where the workout is written down between launches; nil keeps it
    /// only in memory.
    private let snapshots: WorkoutSnapshotStoring?
    /// "Rest over" while the phone is in a pocket; nil says nothing.
    private let restNotifications: RestNotificationScheduling?
    /// The session's clock; tests move it by hand.
    let now: () -> Date

    /// `planWeekday` is the day the week trains this session on, which is the
    /// day finishing it completes; it defaults to the plan day's own weekday.
    init(title: String, day: TrainingDay, planWeekday: String? = nil, service: ActivityServicing, live: WorkoutLiveActivityControlling,
         health: HealthWorkoutWriting? = nil, lifts: LiftServicing? = nil, snapshots: WorkoutSnapshotStoring? = nil,
         restNotifications: RestNotificationScheduling? = nil, now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.title = title
        self.sleep = sleep
        // What this week asks for: the weekly review can make it a deload or
        // a build week without changing the plan.
        self.exercises = day.exercises.map(\.forThisWeek).filter { $0.sets > 0 }
        self.planWeekday = planWeekday ?? day.weekday
        self.service = service
        self.live = live
        self.health = health
        self.lifts = lifts
        self.snapshots = snapshots
        self.restNotifications = restNotifications
        self.now = now
    }

    /// The workout a killed run left behind, as it was. `start()` resumes it.
    init(restoring snapshot: WorkoutSnapshot, service: ActivityServicing, live: WorkoutLiveActivityControlling,
         health: HealthWorkoutWriting? = nil, lifts: LiftServicing? = nil, snapshots: WorkoutSnapshotStoring? = nil,
         restNotifications: RestNotificationScheduling? = nil, now: @escaping () -> Date = Date.init,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        title = snapshot.title
        self.sleep = sleep
        exercises = snapshot.exercises
        planWeekday = snapshot.planWeekday
        self.service = service
        self.live = live
        self.health = health
        self.lifts = lifts
        self.snapshots = snapshots
        self.restNotifications = restNotifications
        self.now = now
        exerciseIndex = snapshot.exerciseIndex
        setNumber = snapshot.setNumber
        completedSets = snapshot.completedSets
        startedAt = snapshot.startedAt
        phase = snapshot.restEndsAt.map { .resting(until: $0) } ?? .working
        isPaused = snapshot.isPaused
        pausedAt = snapshot.pausedAt
        pausedTotal = snapshot.pausedTotal
        restRemaining = snapshot.restRemaining
        recorded = snapshot.recorded
        notice = snapshot.notice
        logged = snapshot.logged
        lastTime = snapshot.lastTime
        restoredActivityID = snapshot.liveActivityID
        isRestored = true
    }

    // MARK: - Doing it

    func start() {
        if isRestored {
            resumeRestored()
            return
        }
        guard phase == .ready, !exercises.isEmpty else { return }
        startedAt = now()
        phase = .working
        live.start(title: title, startedAt: movingSince, state: liveState)
        persist()
        connecting = Task { await connect() }
        loadingLastTime = Task { await loadLastTime() }
    }

    /// Picks up a workout the app was killed during. Rest is measured by the
    /// clock, so one that ran out while the app was gone is over; the Live
    /// Activity left on screen is taken over; sets the server never answered
    /// for are sent again.
    private func resumeRestored() {
        isRestored = false
        if case .resting(let until) = phase, !isPaused, until <= now() {
            phase = .working
        }
        live.reattach(activityID: restoredActivityID, title: title, startedAt: startedAt ?? now(), state: liveState)
        restoredActivityID = nil
        syncRestNotification()
        persist()
        if recorded == nil {
            connecting = Task { await rejoin() }
        }
        if lastTime.isEmpty {
            loadingLastTime = Task { await loadLastTime() }
        }
        for set in logged where set.upload == .pending || set.upload == .failed {
            upload(set)
        }
    }

    private func loadLastTime() async {
        guard let lifts else { return }
        let keys = Array(Set(exercises.map(key(for:)))).sorted()
        if let last = try? await lifts.last(keys) {
            lastTime = last
            persist()
        }
    }

    /// The set in hand is done: rest, then the next one; or the workout is.
    /// With a weight, the set is logged: here at once, on the server as soon
    /// as it answers. A warm-up is logged but leaves the plan where it is:
    /// set 1 is still to come after it.
    func completeSet(weightKg: Double? = nil, reps: Int? = nil, kind: SetKind = .work, rir: Int? = nil) async {
        guard phase == .working, !isPaused, let current else { return }
        if let weightKg {
            record(LoggedSet(exerciseKey: key(for: current), exerciseName: current.name,
                             exerciseSlug: current.catalogSlug, setNumber: setNumber, weightKg: max(0, weightKg),
                             reps: max(1, reps ?? suggestedReps), kind: kind, rir: rir.map { min(max($0, 0), 10) },
                             performedAt: now()))
        }
        guard kind.counts else { return }
        completedSets += 1
        if isLastSet {
            await finish()
            return
        }
        let rest = TimeInterval(current.restSeconds)
        if setNumber < current.sets {
            setNumber += 1
        } else {
            exerciseIndex += 1
            setNumber = 1
        }
        phase = rest > 0 ? .resting(until: now().addingTimeInterval(rest)) : .working
        publish()
    }

    func endRest() {
        guard case .resting = phase, !isPaused else { return }
        phase = .working
        publish()
    }

    func extendRest(by seconds: TimeInterval) {
        guard case .resting(let until) = phase, !isPaused else { return }
        phase = .resting(until: max(until, now()).addingTimeInterval(seconds))
        publish()
    }

    func pause() async {
        guard phase != .ready, phase != .finished, !isPaused else { return }
        isPaused = true
        pausedAt = now()
        if let restEndsAt { restRemaining = max(0, restEndsAt.timeIntervalSince(now())) }
        publish()
        await server { [service] id in try await service.pause(id) }
    }

    func resume() async {
        guard isPaused, let pausedAt else { return }
        pausedTotal += now().timeIntervalSince(pausedAt)
        self.pausedAt = nil
        isPaused = false
        if let restRemaining {
            phase = restRemaining > 0 ? .resting(until: now().addingTimeInterval(restRemaining)) : .working
            self.restRemaining = nil
        }
        publish()
        await server { [service] id in try await service.resume(id) }
    }

    private func record(_ set: LoggedSet) {
        logged.append(set)
        persist()
        upload(set)
    }

    private func upload(_ set: LoggedSet) {
        guard let lifts, !uploading.contains(set.id) else { return }
        uploading.insert(set.id)
        attempts[set.id, default: 0] += 1
        saving.append(Task { [weak self] in
            await self?.connecting?.value
            let input = set.input(activitySessionID: self?.recorded?.id)
            do {
                let saved = try await lifts.log(input)
                self?.finishUpload(set.id, .saved(id: saved.id), retryable: false)
            } catch {
                self?.finishUpload(set.id, .failed, retryable: Self.isWorthRetrying(error))
            }
        })
    }

    private func finishUpload(_ setID: UUID, _ upload: SetUpload, retryable: Bool) {
        uploading.remove(setID)
        if case .saved = upload { attempts[setID] = nil }
        if !retryable { attempts[setID] = attempts[setID].map { max($0, Self.maxAutomaticAttempts) } }
        mark(setID, upload)
        if upload == .failed, retryable { scheduleRetry() }
    }

    private func mark(_ setID: UUID, _ upload: SetUpload) {
        guard let index = logged.firstIndex(where: { $0.id == setID }) else { return }
        logged[index].upload = upload
        persist()
    }

    /// Sends every set the server has not taken again, now. Called when the
    /// app comes back, by the backoff, and before the workout is finished.
    /// A set the server refused for what it is (not for the connection) is
    /// only sent again from here, never by the backoff.
    func retryFailedSets() {
        retrying?.cancel()
        retrying = nil
        for set in logged where set.upload == .failed {
            upload(set)
        }
    }

    /// Waits longer after each try — 2 s, 4 s, 8 s … up to a minute — then
    /// sends the failed sets that still have automatic tries left.
    private func scheduleRetry() {
        guard retrying == nil, phase != .finished else { return }
        let failed = logged.filter { $0.upload == .failed && attempts[$0.id, default: 0] < Self.maxAutomaticAttempts }
        guard let fewest = failed.map({ attempts[$0.id, default: 1] }).min() else { return }
        let delay = Duration.seconds(min(60, 2 << min(fewest - 1, 5)))
        retrying = Task { [weak self, sleep] in
            await sleep(delay)
            guard !Task.isCancelled, let self else { return }
            self.retrying = nil
            for set in self.logged where set.upload == .failed && self.attempts[set.id, default: 0] < Self.maxAutomaticAttempts {
                self.upload(set)
            }
        }
    }

    /// Whether a failed send is worth sending again by itself: the connection
    /// or the server's own trouble, not a refusal of the set.
    nonisolated static func isWorthRetrying(_ error: any Error) -> Bool {
        guard let apiError = error as? APIError else { return true }
        switch apiError {
        case .fieldValidation, .notFound, .unauthorized, .conflict, .locked:
            return false
        case .invalidStatus(let code):
            return code == 408 || code == 429 || code >= 500
        default:
            return true
        }
    }

    /// Ends the workout and records it, sets done or not.
    func finish() async {
        guard phase != .finished else { return }
        if isPaused, let pausedAt {
            pausedTotal += now().timeIntervalSince(pausedAt)
            self.pausedAt = nil
            isPaused = false
        }
        phase = .finished
        live.end(liveState, dismissImmediately: true)
        restNotifications?.cancel()
        snapshots?.clear()
        defer {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        if let health, let startedAt {
            await health.saveStrengthWorkout(start: startedAt, end: now())
        }
        await connecting?.value
        retryFailedSets()
        retrying?.cancel()
        retrying = nil
        for task in saving { await task.value }
        saving = []
        guard let recorded else { return }
        do {
            self.recorded = try await service.stop(recorded.id)
        } catch {
            notice = "The workout finished here, but the server did not record it: \(error.localizedDescription)"
            self.recorded = nil
        }
    }

    /// Throws the workout away, here and on the server.
    func discard() async {
        // Finished first, so the activity's last state is not "working".
        phase = .finished
        live.end(liveState, dismissImmediately: true)
        restNotifications?.cancel()
        snapshots?.clear()
        defer {
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        await connecting?.value
        for task in saving { await task.value }
        saving = []
        if let lifts {
            for id in logged.compactMap(\.serverID) { try? await lifts.delete(id) }
        }
        logged = []
        if let recorded {
            do { try await service.cancel(recorded.id) } catch { notice = error.localizedDescription }
        }
        recorded = nil
    }

    // MARK: - The server session

    /// Starts the server's timer, or joins one already open on the account
    /// (started on the web, or before the app was quit).
    private func connect() async {
        defer { persist() }
        do {
            recorded = try await service.start(Self.activityCode, planWeekday: planWeekday)
            return
        } catch {
            if let open = try? await service.openSession(), open.status == .active || open.status == .paused {
                recorded = open
                notice = "Continuing the \(open.activityName.lowercased()) session already running on your account."
                return
            }
            notice = "This workout is not being recorded: \(error.localizedDescription)"
        }
    }

    /// A restored workout whose server session never answered: joins the one
    /// open on the account, if the start did reach the server. Starting a
    /// new one now would time the workout from the wrong moment.
    private func rejoin() async {
        guard let open = try? await service.openSession(),
              open.status == .active || open.status == .paused else { return }
        recorded = open
        persist()
    }

    private func server(_ call: @escaping (String) async throws -> ActivitySession) async {
        await connecting?.value
        guard let id = recorded?.id else { return }
        do {
            recorded = try await call(id)
        } catch {
            notice = error.localizedDescription
        }
        persist()
    }

    // MARK: - Outside the app

    /// Tells everything outside the session where it is now: the Live
    /// Activity, the rest-end notification and the snapshot.
    private func publish() {
        live.update(liveState)
        syncRestNotification()
        persist()
    }

    /// A notification for the end of the rest under way; none while working
    /// or paused. Scheduling again replaces the last one.
    private func syncRestNotification() {
        guard let restNotifications else { return }
        if let restEnd { restNotifications.schedule(restEnd) } else { restNotifications.cancel() }
    }

    private func persist() {
        guard let snapshots, let snapshot else { return }
        snapshots.save(snapshot)
    }

    /// The Lock Screen activity, or the one a restored workout is about to
    /// take over.
    var liveActivityID: String? { live.activityID ?? restoredActivityID }
}

/// Presented with `fullScreenCover(item:)`; identity is the instance.
extension WorkoutSession: Identifiable {}
