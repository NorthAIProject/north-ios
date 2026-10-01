import NorthAPI
import NorthKit
import SwiftUI

/// The Training tab: the plan being followed, day by day, each marked done
/// this week or next as the server counts them.
struct TrainingScreen: View {
    @State private var store = TrainingStore(timeZone: { AppTimeZone.current })
    @State private var path: [DayRoute] = []
    @State private var creating = false
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Training")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            NavigationLink(value: DayRoute.library) {
                                Label("Exercise Library", systemImage: "books.vertical")
                            }
                            NavigationLink(value: DayRoute.formCheck) {
                                Label("Form Check", systemImage: "video.badge.checkmark")
                            }
                            NavigationLink(value: DayRoute.history) {
                                Label("Activity History", systemImage: "clock.arrow.circlepath")
                            }
                            Button("New Plan", systemImage: "plus") { creating = true }
                        } label: {
                            Label("Training Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
                .navigationDestination(for: DayRoute.self) { route in
                    switch route {
                    case .day(let index): DayView(store: store, dayIndex: index)
                    case .library: ExerciseLibrary(service: store.service)
                    case .formCheck: FormCheckScreen()
                    case .history: ActivityHistoryScreen()
                    }
                }
                .refreshable { await store.load() }
                .sheet(isPresented: $creating) {
                    IntakeSheet(service: store.service) { plan in
                        Task { await store.show(plan) }
                    }
                }
        }
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
        // Back from a day, possibly from finishing its workout: the server
        // now counts that day done, so read the plan again.
        .onChange(of: path) { old, new in
            if new.isEmpty, !old.isEmpty { Task { await store.load() } }
        }
        // A reminder's Start Workout, or a khepri://training link, lands here.
        .onChange(of: router.openTrainingDay, initial: true) { _, day in
            guard let day else { return }
            router.openTrainingDay = nil
            path = [.day(day)]
        }
        // Start Today's Workout names no day; the plan decides which is next.
        .onChange(of: [router.opensNextWorkout != nil, store.plan != nil], initial: true) {
            guard let start = router.opensNextWorkout, let plan = store.plan else { return }
            router.opensNextWorkout = nil
            guard let day = plan.nextDayIndex else { return }
            router.startsWorkout = start
            path = [.day(day)]
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Training did not load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
        case .empty:
            ContentUnavailableView {
                Label("No plan yet", systemImage: "figure.strengthtraining.traditional")
            } description: {
                Text("Tell your coach what you're training for, how often, and with what. You'll get a plan to follow and adjust.")
            } actions: {
                Button("Create a Plan") { creating = true }
                    .northProminentButton()
            }
            .anchorGuidedTour(.training)
        case .ready:
            if let plan = store.plan {
                PlanOverview(plan: plan, notice: store.notice)
            }
        }
    }
}

enum DayRoute: Hashable {
    case day(Int)
    case library
    case formCheck
    case history
}

/// The plan: why it suits the person, then each day.
private struct PlanOverview: View {
    let plan: PlanDetail
    let notice: String?

    var body: some View {
        List {
            if let notice {
                Section { Label(notice, systemImage: "arrow.triangle.2.circlepath").font(.subheadline) }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.name)
                        .font(.north(.title2).weight(.semibold))
                    Text("\(plan.weeksTotal) weeks · \(plan.days.count) days a week")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !plan.rationale.isEmpty {
                        Text(plan.rationale)
                            .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .anchorGuidedTour(.training)
            }

            Section("Days") {
                ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                    NavigationLink(value: DayRoute.day(index)) {
                        DayRow(day: day)
                    }
                }
            }

            if !plan.problems.isEmpty {
                Section {
                    ForEach(plan.problems, id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                    }
                } header: {
                    Text("Worth a look")
                } footer: {
                    Text("Where the plan no longer matches what you asked for. Edits are yours to make; nothing is changed for you.")
                }
            }
        }
    }
}

private struct DayRow: View {
    let day: TrainingDay

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(day.weekday).font(.headline)
                    switch day.status {
                    case .completed:
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .northEyebrow()
                    case .next:
                        Text("Next")
                            .northEyebrow(NorthColor.signal)
                    case nil:
                        EmptyView()
                    }
                }
                Text(day.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let start = day.startTime {
                    Label(start, systemImage: "bell")
                        .font(.subheadline.monospacedDigit())
                        .labelStyle(.titleAndIcon)
                }
                Text("\(day.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Where a plan day stands this week. The server decides both, from the
/// sessions it has recorded, so the phone and the web always agree.
enum DayStatus: Equatable {
    case completed
    case next
}

extension TrainingDay {
    var status: DayStatus? {
        if completedThisWeek { return .completed }
        if isNext { return .next }
        return nil
    }
}

extension PlanDetail {
    /// The day to train next: the first one not yet done this week, or next
    /// week's first once everything is.
    var nextDayIndex: Int? { days.firstIndex(where: \.isNext) }
}

/// The account's time zone, for scheduling. Kept here rather than read from
/// the device, because plans and reminders follow the account.
enum AppTimeZone {
    @MainActor static var current: TimeZone = .current
}
