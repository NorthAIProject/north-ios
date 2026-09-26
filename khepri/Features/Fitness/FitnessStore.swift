import Foundation
import NorthAPI

/// Everything the Fitness screen shows: Apple Health read on the phone, and
/// weight and goal from the server.
@MainActor
@Observable
final class FitnessStore {
    enum Phase: Equatable { case loading, ready }

    private(set) var phase: Phase = .loading
    private(set) var snapshot = FitnessSnapshot()
    private(set) var calculator: Calculator?
    private(set) var syncing = false
    private(set) var lastSync: Date?

    let source: FitnessDataSource
    let calculatorService: CalculatorServicing
    private let sync: @Sendable () async -> Date?
    private let now: () -> Date
    let calendar: Calendar

    init(source: FitnessDataSource = HealthKitFitnessSource(),
         calculatorService: CalculatorServicing = CalculatorService(),
         sync: @escaping @Sendable () async -> Date? = FitnessStore.syncHealth,
         now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current) {
        self.source = source
        self.calculatorService = calculatorService
        self.sync = sync
        self.now = now
        self.calendar = calendar
        self.lastSync = HealthSync.shared.lastReport?.at
    }

    nonisolated static func syncHealth() async -> Date? {
        _ = try? await HealthSync.shared.syncIfEnabled()
        return HealthSync.shared.lastReport?.at
    }

    var isHealthAvailable: Bool { source.isAvailable }
    var week: FitnessWeek { FitnessWeek(snapshot: snapshot, now: now(), calendar: calendar) }
    var recentSteps: [StepDay] { StepDay.recent(snapshot.steps) }
    var today: Date { now() }

    /// The average over the steps window, for "9.3k / day".
    var averageSteps: Double {
        let values = snapshot.steps.map(\.value)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    var weightKg: Double? { calculator?.biometrics?.weightKg }

    var vo2Rating: VO2Rating? {
        guard let latest = snapshot.vo2Max.last else { return nil }
        return VO2Rating.rating(for: latest.value, age: age, sex: calculator?.biometrics?.sex)
    }

    private var age: Int? {
        guard let text = calculator?.biometrics?.dateOfBirth, let born = CalendarDay.date(from: text) else { return nil }
        return calendar.dateComponents([.year], from: born, to: now()).year
    }

    /// Reads Apple Health and the body measurements together.
    func load() async {
        async let activity: Void = loadActivity()
        async let body: Void = loadBody()
        _ = await (activity, body)
    }

    /// Apple Health only: what Today's week card needs.
    func loadActivity() async {
        if let fresh = try? await source.snapshot(now: now(), calendar: calendar) {
            snapshot = fresh
        }
        phase = .ready
    }

    func loadBody() async {
        if let fresh = try? await calculatorService.calculator() {
            calculator = fresh
        }
    }

    /// Sends Apple Health to the server, then reads everything again.
    func refresh() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        if let at = await sync() { lastSync = at }
        await load()
    }
}
