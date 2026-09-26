import Foundation
import NorthAPI
import NorthKit
import Observation

/// One training day, done: set by set, with rest between, timed on the
/// server so the web, the coach and calorie totals see it.
///
/// The workout never waits on the network. It runs here from the first tap;
/// the server session is joined as soon as it answers, and when the server
/// refuses (no body weight yet, say) the workout goes on and the finish says
/// why it was not recorded.
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
    private(set) var unsavedSets = 0

    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    /// Rest left when paused mid-rest, restored on resume.
    private var restRemaining: TimeInterval?
    private var connecting: Task<Void, Never>?
    private var saving: [Task<Void, Never>] = []
    /// Last time's numbers arriving; tests wait on it.
    private(set) var loadingLastTime: Task<Void, Never>?
    /// The server's ids for the sets it took, so a discard can take them back.
    private var savedIDs: [String] = []

    private let service: ActivityServicing
    private let live: WorkoutLiveActivityControlling
    /// Saves the finished workout to Apple Health, when allowed.
    private let health: HealthWorkoutWriting?
    /// Where each set's weight and reps go; nil keeps them on the phone.
    private let lifts: LiftServicing?
    private let now: () -> Date

    init(title: String, day: TrainingDay, service: ActivityServicing, live: WorkoutLiveActivityControlling,
         health: HealthWorkoutWriting? = nil, lifts: LiftServicing? = nil, now: @escaping () -> Date = Date.init) {
        self.title = title
        self.exercises = day.exercises.filter { $0.sets > 0 }
        self.service = service
        self.live = live
        self.health = health
        self.lifts = lifts
        self.now = now
    }

    /// One set as it was done.
    struct LoggedSet: Equatable {
        let exerciseKey: String
        let exerciseName: String
        let setNumber: Int
        let weightKg: Double
        let reps: Int

        var volumeKg: Double { weightKg * Double(reps) }
        var e1rmKg: Double { LiftMath.e1rm(weightKg: weightKg, reps: reps) }
    }

    // MARK: - Where the workout is

    var current: DayExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }

    var next: DayExercise? {
        guard let current else { return nil }
        if setNumber < current.sets { return current }
        return exercises.indices.contains(exerciseIndex + 1) ? exercises[exerciseIndex + 1] : nil
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    var isLastSet: Bool { exerciseIndex == exercises.count - 1 && setNumber == (current?.sets ?? 0) }

    /// Start moved later by paused time: a timer from here shows moving time.
    var movingSince: Date { (startedAt ?? now()).addingTimeInterval(pausedTotal) }

    var movingTime: TimeInterval {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? now()
        return end.timeIntervalSince(startedAt) - pausedTotal
    }

    var restEndsAt: Date? { if case .resting(let until) = phase { until } else { nil } }

    // MARK: - Weights

    func key(for exercise: DayExercise) -> String { LiftMath.key(slug: exercise.catalogSlug, name: exercise.name) }

    /// What the set in hand starts from: this workout's previous set of the
    /// exercise, else the same set last time, else last time's final set.
    /// Nil when the exercise has never been done with a weight.
    var suggestedWeightKg: Double? {
        guard let current else { return nil }
        let key = key(for: current)
        if let previous = logged.last(where: { $0.exerciseKey == key }) { return previous.weightKg }
        let last = lastTime[key] ?? []
        return (last.first { $0.setNumber == setNumber } ?? last.last)?.weightKg
    }

    /// Reps start from the plan's number, else last time's.
    var suggestedReps: Int {
        guard let current else { return 1 }
        if let planned = LiftMath.reps(from: current.reps) { return planned }
        let last = lastTime[key(for: current)] ?? []
        return (last.first { $0.setNumber == setNumber } ?? last.last)?.reps ?? 10
    }

    /// Last time's sets of the exercise in hand, for "last time" under the
    /// weight field.
    var lastTimeForCurrent: [LiftSet] {
        guard let current else { return [] }
        return lastTime[key(for: current)] ?? []
    }

    var volumeKg: Double { logged.reduce(0) { $0 + $1.volumeKg } }

    /// Exercises whose best set today beat every set of the last workout, by
    /// estimated max.
    var improvements: [LoggedSet] {
        var best: [String: LoggedSet] = [:]
        for set in logged where set.weightKg > 0 {
            if set.e1rmKg > (best[set.exerciseKey]?.e1rmKg ?? 0) { best[set.exerciseKey] = set }
        }
        return best.values.filter { set in
            let previous = (lastTime[set.exerciseKey] ?? []).map(\.e1rmKg).max() ?? 0
            return previous > 0 && set.e1rmKg > previous + 0.05
        }
        .sorted { $0.exerciseName < $1.exerciseName }
    }

    // MARK: - Doing it

    func start() {
        guard phase == .ready, !exercises.isEmpty else { return }
        startedAt = now()
        phase = .working
        live.start(title: title, startedAt: movingSince, state: liveState)
        connecting = Task { await connect() }
        loadingLastTime = Task { await loadLastTime() }
    }

    private func loadLastTime() async {
        guard let lifts else { return }
        let keys = Array(Set(exercises.map(key(for:)))).sorted()
        if let last = try? await lifts.last(keys) { lastTime = last }
    }

    /// The set in hand is done: rest, then the next one; or the workout is.
    /// With a weight, the set is logged: here at once, on the server as soon
    /// as it answers.
    func completeSet(weightKg: Double? = nil, reps: Int? = nil) async {
        guard phase == .working, !isPaused, let current else { return }
        if let weightKg {
            record(LoggedSet(exerciseKey: key(for: current), exerciseName: current.name, setNumber: setNumber,
                             weightKg: max(0, weightKg), reps: max(1, reps ?? suggestedReps)), exercise: current)
        }
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
        live.update(liveState)
    }

    func endRest() {
        guard case .resting = phase, !isPaused else { return }
        phase = .working
        live.update(liveState)
    }

    func extendRest(by seconds: TimeInterval) {
        guard case .resting(let until) = phase, !isPaused else { return }
        phase = .resting(until: max(until, now()).addingTimeInterval(seconds))
        live.update(liveState)
    }

    func pause() async {
        guard phase != .ready, phase != .finished, !isPaused else { return }
        isPaused = true
        pausedAt = now()
        if let restEndsAt { restRemaining = max(0, restEndsAt.timeIntervalSince(now())) }
        live.update(liveState)
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
        live.update(liveState)
        await server { [service] id in try await service.resume(id) }
    }

    private func record(_ set: LoggedSet, exercise: DayExercise) {
        logged.append(set)
        guard let lifts else { return }
        let performedAt = now()
        saving.append(Task { [weak self] in
            await self?.connecting?.value
            let input = Components.Schemas.LiftSetInput(
                exerciseName: set.exerciseName, exerciseSlug: exercise.catalogSlug, setNumber: set.setNumber,
                weightKg: set.weightKg, reps: set.reps, performedAt: performedAt, activitySessionId: self?.recorded?.id)
            do {
                let saved = try await lifts.log(input)
                self?.savedIDs.append(saved.id)
            } catch {
                self?.unsavedSets += 1
            }
        })
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
        live.end(liveState, dismissImmediately: false)
        if let health, let startedAt {
            await health.saveStrengthWorkout(start: startedAt, end: now())
        }
        await connecting?.value
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
        live.end(liveState, dismissImmediately: true)
        phase = .finished
        await connecting?.value
        for task in saving { await task.value }
        saving = []
        if let lifts {
            for id in savedIDs { try? await lifts.delete(id) }
        }
        savedIDs = []
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
        do {
            recorded = try await service.start(Self.activityCode)
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

    private func server(_ call: @escaping (String) async throws -> ActivitySession) async {
        await connecting?.value
        guard let id = recorded?.id else { return }
        do {
            recorded = try await call(id)
        } catch {
            notice = error.localizedDescription
        }
    }

    var liveState: WorkoutLiveState {
        WorkoutLiveState(
            exerciseName: current?.name ?? title,
            setNumber: setNumber,
            totalSets: current?.sets ?? 0,
            phase: isPaused ? .paused : (restEndsAt == nil ? .working : .resting),
            restEndsAt: restEndsAt,
            exerciseNumber: min(exerciseIndex + 1, exercises.count),
            totalExercises: exercises.count,
            movingSince: movingSince
        )
    }
}

/// Presented with `fullScreenCover(item:)`; identity is the instance.
extension WorkoutSession: Identifiable {}
