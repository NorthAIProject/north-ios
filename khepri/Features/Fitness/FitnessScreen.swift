import Charts
import NorthKit
import SwiftUI

/// Where Today's week card leads.
struct FitnessRoute: Hashable {}

/// Movement at a glance: the week, recent workouts, weight, and how steps and
/// VO2 max are trending. Read from Apple Health on the phone, so it works
/// before anything has synced.
struct FitnessScreen: View {
    @State private var store = FitnessStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.phase == .loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    if store.snapshot.isEmpty {
                        ConnectHealthCard(available: store.isHealthAvailable) {
                            await Permissions.requestHealth()
                            await store.load()
                        }
                    }
                    FitnessWeekCard(week: store.week)
                    HealthSyncRow(lastSync: store.lastSync)
                    RecentWorkouts(workouts: store.snapshot.workouts, thisWeek: store.week.workouts)
                    WeightGoalCard(weightKg: store.weightKg, calculator: store.calculator)
                    if !store.snapshot.steps.isEmpty {
                        StepsCard(steps: store.snapshot.steps, recent: store.recentSteps, average: store.averageSteps)
                    }
                    if let latest = store.snapshot.vo2Max.last {
                        Vo2MaxCard(series: store.snapshot.vo2Max, latest: latest, rating: store.vo2Rating)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(.snappy, value: store.snapshot)
        }
        .navigationTitle("Fitness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.syncing {
                    ProgressView()
                } else {
                    Button("Sync", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                }
            }
        }
        .refreshable { await store.refresh() }
        .task {
            // Asks only for types not yet answered, such as VO2 max for
            // people who connected Health before this screen existed.
            if HealthSync.shared.isEnabled { await Permissions.requestHealth() }
            await store.load()
        }
        // Back from logging weight or changing the goal.
        .onAppear { if store.phase == .ready { Task { await store.loadBody() } } }
    }
}

// MARK: - Apple Health

private struct ConnectHealthCard: View {
    let available: Bool
    let connect: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple Health", systemImage: "heart.fill")
                .font(.north(.headline))
                .foregroundStyle(.pink)
            Text(available
                 ? "Nothing from Apple Health yet. Allow Khepri to read steps, workouts and VO2 max to fill this in."
                 : "Apple Health is not available on this device.")
                .font(.north(.subheadline))
                .foregroundStyle(.secondary)
            if available {
                Button("Connect Apple Health") { Task { await connect() } }
                    .northProminentButton()
            }
        }
        .northSurfaceCard()
    }
}

private struct HealthSyncRow: View {
    let lastSync: Date?

    var body: some View {
        NavigationLink {
            HealthSettings()
        } label: {
            HStack {
                Group {
                    if let lastSync {
                        Text("Apple Health · synced \(Text(lastSync, format: .relative(presentation: .named)))")
                    } else {
                        Text("Apple Health · not synced yet")
                    }
                }
                .font(.north(.subheadline))
                .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workouts

private struct RecentWorkouts: View {
    let workouts: [FitnessWorkout]
    let thisWeek: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NorthCardHeader("Recent", detail: thisWeek > 0 ? "\(thisWeek) this week" : nil) {
                NavigationLink("See all") { ActivityHistoryScreen() }
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            if workouts.isEmpty {
                Text("No workouts in the last month.")
                    .font(.north(.subheadline))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(workouts.prefix(5).enumerated()), id: \.element.id) { index, workout in
                    if index > 0 { Divider().padding(.leading, 64) }
                    WorkoutRow(workout: workout)
                }
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: FitnessWorkout

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: workout.systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.north(.headline))
                Text(detail)
                    .font(.north(.subheadline))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(workout.start, format: .dateTime.month(.abbreviated).day())
                Text(workout.start, format: .dateTime.hour().minute())
            }
            .font(.north(.subheadline))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [FitnessFormat.duration(workout.duration)]
        if let km = workout.km, km >= 0.05 { parts.append(FitnessFormat.km(km)) }
        if let pace = workout.paceSecondsPerKm { parts.append(FitnessFormat.pace(pace)) }
        return parts.joined(separator: " · ")
    }
}

/// An SF Symbol in a soft circle, leading a row.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(Color(.tertiarySystemFill), in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: - Weight and goal

private struct WeightGoalCard: View {
    let weightKg: Double?
    let calculator: Calculator?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NorthCardHeader("Weight") {
                NavigationLink("Log weight") { BodyAndGoalScreen() }
            }
            if let weightKg {
                NorthBigValue(Measurement(value: weightKg, unit: UnitMass.kilograms)
                    .formatted(.measurement(width: .abbreviated, usage: .personWeight, numberFormatStyle: .number.precision(.fractionLength(0...1)))),
                    style: .title)
            } else {
                Text("No weight logged yet.")
                    .font(.north(.title3))
                    .foregroundStyle(.secondary)
            }

            Divider()

            NorthCardHeader("Goal") {
                NavigationLink(calculator?.goal == nil ? "Set goal" : "Change") { BodyAndGoalScreen() }
            }
            if let goal = calculator?.goal {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.goal.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.north(.title3).weight(.semibold))
                    Text("\(Int(goal.calorieGoal.rounded())) kcal a day · \(Int(goal.proteinG.rounded())) g protein")
                        .font(.north(.subheadline))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active weight goal.")
                    .font(.north(.title3))
                    .foregroundStyle(.secondary)
            }
        }
        .northSurfaceCard()
    }
}

// MARK: - Steps

private struct StepsCard: View {
    let steps: [DailyValue]
    let recent: [StepDay]
    let average: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NorthCardHeader("Steps")
            if let latest = steps.last {
                HStack(alignment: .firstTextBaseline) {
                    NorthBigValue(FitnessFormat.compact(latest.value), unit: "steps")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(FitnessFormat.compact(average)) / day")
                            .font(.north(.title3))
                            .foregroundStyle(.secondary)
                        Text(latest.day, format: .dateTime.month(.abbreviated).day())
                            .font(.north(.subheadline))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            TrendChart(series: steps, tint: .cyan)
                .frame(height: 120)

            NorthInsetList(recent, id: \.id) { day in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(FitnessFormat.compact(day.steps)) steps")
                            .font(.north(.body).weight(.medium))
                        Text(day.day, format: .dateTime.month(.abbreviated).day().year())
                            .font(.north(.subheadline))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let delta = day.delta {
                        Text(FitnessFormat.signed(delta))
                            .font(.north(.subheadline).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(delta > 0 ? Color.green : delta < 0 ? Color.red : Color.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .northSurfaceCard()
    }
}

// MARK: - VO2 max

private struct Vo2MaxCard: View {
    let series: [DailyValue]
    let latest: DailyValue
    let rating: VO2Rating?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NorthCardHeader("VO2 max") {
                Menu {
                    Text("VO2 max is how much oxygen your body can use during hard exercise. Apple Watch estimates it from outdoor walks, runs and hikes.")
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("About VO2 max")
            }
            HStack(alignment: .firstTextBaseline) {
                NorthBigValue(latest.value.formatted(.number.precision(.fractionLength(1))), unit: "ml/kg/min")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let rating {
                        Text(rating.rawValue)
                            .font(.north(.title3).weight(.semibold))
                            .foregroundStyle(rating.tint)
                    }
                    Text(latest.day, format: .dateTime.month(.abbreviated).day())
                        .font(.north(.subheadline))
                        .foregroundStyle(.tertiary)
                }
            }
            TrendChart(series: series, tint: .indigo, fromZero: false)
                .frame(height: 100)
        }
        .northSurfaceCard()
    }
}

extension VO2Rating {
    var tint: Color {
        switch self {
        case .poor: .red
        case .fair: .yellow
        case .good: .green
        case .excellent: .mint
        }
    }
}

// MARK: - Chart

/// A line with a soft fill beneath it and a dot on the latest value.
struct TrendChart: View {
    let series: [DailyValue]
    let tint: Color
    var fromZero = true

    private var domain: ClosedRange<Double> {
        let values = series.map(\.value)
        let high = values.max() ?? 1
        guard !fromZero else { return 0...max(high, 1) }
        let low = values.min() ?? 0
        let pad = max((high - low) * 0.5, 2)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        Chart {
            ForEach(series, id: \.day) { point in
                AreaMark(x: .value("Day", point.day, unit: .day),
                         yStart: .value("Base", domain.lowerBound),
                         yEnd: .value("Value", point.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("Value", point.value))
                    .interpolationMethod(.linear)
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let last = series.last {
                PointMark(x: .value("Day", last.day, unit: .day), y: .value("Value", last.value))
                    .foregroundStyle(tint)
                    .symbolSize(60)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .accessibilityHidden(true)
    }
}
