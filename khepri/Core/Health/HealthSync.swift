import Foundation
import HealthKit
import NorthAPI
import os

/// Uploads a batch to the server. A protocol for the sync's tests.
protocol HealthUploading: Sendable {
    func sync(_ request: HealthSyncRequest) async throws -> Components.Schemas.HealthSyncResult
    func forget() async throws
}

struct HealthService: HealthUploading {
    var api: Client = API.shared

    func sync(_ request: HealthSyncRequest) async throws -> Components.Schemas.HealthSyncResult {
        try await NorthAPI.call { try await api.syncHealth(body: .json(request)).ok.body.json }
    }

    func forget() async throws {
        try await NorthAPI.call { _ = try await api.forgetHealth().noContent }
    }
}

/// What the last sync did, for the settings row.
struct HealthSyncReport: Codable, Equatable {
    var at: Date
    var readings: Int
    var workouts: Int
}

/// Syncs Apple Health to the server: on opening the app, from Settings, and
/// when HealthKit wakes the app in the background with new data.
///
/// An actor, because those three can arrive at once and two overlapping syncs
/// would upload the same days twice for nothing.
actor HealthSync {
    static let shared = HealthSync()

    /// How far back the first sync reads.
    static let firstSyncDays = 30
    /// How far before the last sync each later one starts again: a watch
    /// hands its data to the phone late, and today's totals keep growing.
    static let overlapDays = 2

    private let source: HealthDataSource
    private let uploader: HealthUploading
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private var running: Task<HealthSyncReport, Error>?
    private let log = Logger(subsystem: "com.fernandocorreia.khepri", category: "health-sync")

    init(source: HealthDataSource = HealthKitSource(), uploader: HealthUploading = HealthService(),
         defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.source = source
        self.uploader = uploader
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Settings

    static let enabledKey = "health.sync.enabled"
    static let lastReportKey = "health.sync.lastReport"

    /// Set when the person connects Apple Health, in the wizard or Settings.
    nonisolated var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
    }

    nonisolated func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    nonisolated var lastReport: HealthSyncReport? {
        defaults.data(forKey: Self.lastReportKey).flatMap { try? JSONDecoder().decode(HealthSyncReport.self, from: $0) }
    }

    // MARK: - Syncing

    /// Syncs unless it is off or unavailable; a sync already running is
    /// joined, not repeated. Returns nil when nothing ran.
    @discardableResult
    func syncIfEnabled(calendar: Calendar = .current) async throws -> HealthSyncReport? {
        guard isEnabled, source.isAvailable else { return nil }
        if let running { return try await running.value }
        let task = Task { try await self.run(calendar: calendar) }
        running = task
        defer { running = nil }
        return try await task.value
    }

    private func run(calendar: Calendar) async throws -> HealthSyncReport {
        let end = now()
        let start: Date
        if let last = lastReport?.at {
            start = calendar.date(byAdding: .day, value: -Self.overlapDays, to: calendar.startOfDay(for: last)) ?? last
        } else {
            start = calendar.date(byAdding: .day, value: -Self.firstSyncDays, to: calendar.startOfDay(for: end)) ?? end
        }

        let snapshot = try await source.snapshot(from: start, to: end, calendar: calendar)
        var report = HealthSyncReport(at: end, readings: 0, workouts: 0)
        for request in HealthPayload.requests(from: snapshot, calendar: calendar) {
            let result = try await uploader.sync(request)
            report.readings += result.readings
            report.workouts += result.workouts
        }
        defaults.set(try? JSONEncoder().encode(report), forKey: Self.lastReportKey)
        log.info("synced \(report.readings) readings, \(report.workouts) workouts")
        return report
    }

    /// Stops syncing and deletes what Apple Health sent. Workouts already in
    /// the activity history stay; the server keeps those.
    func disconnect() async throws {
        try await uploader.forget()
        setEnabled(false)
        defaults.removeObject(forKey: Self.lastReportKey)
    }
}

/// Wakes the app when Apple Health has new workouts, steps or sleep, so the
/// coach sees a morning run without the app being opened.
///
/// Observer queries must be registered on every launch, before the app
/// finishes launching, or background deliveries are dropped.
enum HealthBackgroundDelivery {
    static let types: [HKSampleType] = [
        HKObjectType.workoutType(),
        HKQuantityType(.stepCount),
        HKQuantityType(.restingHeartRate),
        HKCategoryType(.sleepAnalysis),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.dietaryWater),
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.bodyMass),
    ]

    static func register(store: HKHealthStore = HealthStore.shared, sync: HealthSync = .shared) {
        guard HKHealthStore.isHealthDataAvailable(), sync.isEnabled else { return }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    _ = try? await sync.syncIfEnabled()
                    completion()
                }
            }
            store.execute(query)
            // Hourly is the most HealthKit grants most types; workouts arrive
            // as soon as the system allows.
            let frequency: HKUpdateFrequency = type == HKObjectType.workoutType() ? .immediate : .hourly
            store.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
        }
    }
}

/// Saves workouts done in the app to Apple Health, so rings and other apps
/// see them. The sync skips workouts this app wrote, so nothing loops back.
protocol HealthWorkoutWriting: Sendable {
    func saveStrengthWorkout(start: Date, end: Date) async
}

struct HealthWorkoutWriter: HealthWorkoutWriting {
    var store: HKHealthStore = HealthStore.shared

    func saveStrengthWorkout(start: Date, end: Date) async {
        guard HKHealthStore.isHealthDataAvailable(),
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized,
              end > start else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            Logger(subsystem: "com.fernandocorreia.khepri", category: "health-sync")
                .error("workout not saved to Health: \(error.localizedDescription, privacy: .public)")
        }
    }
}
