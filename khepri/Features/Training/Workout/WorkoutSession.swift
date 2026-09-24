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

    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    /// Rest left when paused mid-rest, restored on resume.
    private var restRemaining: TimeInterval?
    private var connecting: Task<Void, Never>?

    private let service: ActivityServicing
    private let live: WorkoutLiveActivityControlling
    private let now: () -> Date

    init(title: String, day: TrainingDay, service: ActivityServicing, live: WorkoutLiveActivityControlling,
         now: @escaping () -> Date = Date.init) {
        self.title = title
        self.exercises = day.exercises.filter { $0.sets > 0 }
        self.service = service
        self.live = live
        self.now = now
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

    // MARK: - Doing it

    func start() {
        guard phase == .ready, !exercises.isEmpty else { return }
        startedAt = now()
        phase = .working
        live.start(title: title, startedAt: movingSince, state: liveState)
        connecting = Task { await connect() }
    }

    /// The set in hand is done: rest, then the next one; or the workout is.
    func completeSet() async {
        guard phase == .working, !isPaused, let current else { return }
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
        await connecting?.value
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
