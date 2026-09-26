import NorthAPI
import NorthKit
import SwiftUI

/// The day at a glance: the briefing, the day's numbers, the one next step,
/// the week's movement, goals, and what happened recently.
struct TodayView: View {
    let snapshot: TodaySnapshot
    var dayStore: DayStore?
    @Environment(AppRouter.self) private var router
    @State private var fitness = FitnessStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Header(briefing: snapshot.briefing)

                StatGrid(snapshot: snapshot) { router.open(.checkInFlow) }
                    // Without a next step, the tour points at the day's numbers.
                    .modifier(TourAnchorIf(step: .today, when: snapshot.nextStep == nil))

                if let nextStep = snapshot.nextStep {
                    NextStepCard(step: nextStep) {
                        if nextStep.kind == "check_in" {
                            router.open(.checkInFlow)
                        } else if let url = URL(string: nextStep.href) {
                            router.open(url: url)
                        }
                    }
                    .anchorGuidedTour(.today)
                }

                if fitness.isHealthAvailable {
                    NavigationLink(value: FitnessRoute()) {
                        FitnessWeekCard(week: fitness.week, compact: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Fitness")
                }

                if let day = dayStore?.day {
                    DayDashboard(day: day, store: dayStore)
                }

                GoalsCard(goals: snapshot.goals)

                // My Day draws its own timeline; this is the fallback while it loads.
                if dayStore?.day == nil, !snapshot.timeline.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        NorthCardHeader("Recently")
                        ForEach(Array(snapshot.timeline.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { Divider().padding(.leading, 58) }
                            TimelineRow(entry: entry)
                        }
                    }
                    .northSurfaceCard(padding: 16)
                }

                NewsSection()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.snappy, value: fitness.snapshot)
        }
        .onAppear { Task { await fitness.loadActivity() } }
    }
}

/// The date and the coach's line for the day.
private struct Header: View {
    let briefing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .northEyebrow()
            if let briefing, !briefing.isEmpty {
                Text(briefing)
                    .font(.north(.title3).weight(.medium))
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// Streak, check-in, water and sleep as four tiles.
private struct StatGrid: View {
    let snapshot: TodaySnapshot
    let checkIn: () -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "Streak", systemImage: "flame.fill", tint: NorthColor.ember,
                         value: snapshot.streak.formatted(), unit: snapshot.streak == 1 ? "day" : "days")
                if snapshot.checkedInToday {
                    StatTile(title: "Check-in", systemImage: "checkmark.circle.fill", tint: .green, value: "Done")
                } else {
                    Button(action: checkIn) {
                        StatTile(title: "Check-in", systemImage: "circle.dashed", tint: NorthColor.signal,
                                 value: "Open", showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            GridRow {
                StatTile(title: "Water", systemImage: "drop.fill", tint: .cyan,
                         value: (Double(snapshot.hydration.todayML) / 1000).formatted(.number.precision(.fractionLength(1))),
                         unit: "of \((Double(snapshot.hydration.targetML) / 1000).formatted(.number.precision(.fractionLength(0...1)))) L",
                         progress: snapshot.hydration.targetML > 0 ? Double(snapshot.hydration.todayML) / Double(snapshot.hydration.targetML) : nil)
                StatTile(title: "Sleep", systemImage: "moon.fill", tint: .indigo,
                         value: snapshot.sleep.logged ? sleepHours : "–",
                         unit: snapshot.sleep.logged ? "h" : "not logged")
            }
        }
    }

    private var sleepHours: String {
        (Double(snapshot.sleep.durationMinutes) / 60).formatted(.number.precision(.fractionLength(1)))
    }
}

private struct StatTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    let value: String
    var unit: String?
    var progress: Double?
    var showsChevron = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title).northEyebrow()
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            NorthBigValue(value, unit: unit, style: .title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(tint)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .northSurfaceCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct GoalsCard: View {
    let goals: [TodayGoal]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NorthCardHeader("Goals", detail: goals.isEmpty ? nil : "\(goals.count) active")
            if goals.isEmpty {
                Text("No active goals yet.")
                    .font(.north(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                NorthInsetList(goals, id: \.id) { GoalRow(goal: $0) }
            }
        }
        .northSurfaceCard()
    }
}

private struct TourAnchorIf: ViewModifier {
    let step: TourStep
    let when: Bool

    func body(content: Content) -> some View {
        if when { content.anchorGuidedTour(step) } else { content }
    }
}

private struct NextStepCard: View {
    let step: TodayNextStep
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.eyebrow)
                .northEyebrow(NorthColor.signal)
            Text(step.title)
                .font(.north(.title2).weight(.bold))
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(step.cta, action: action)
                .northProminentButton()
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .northSurfaceCard()
    }
}

private struct GoalRow: View {
    let goal: TodayGoal

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.north(.body).weight(.medium))
                Text(goal.category.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let progress = goal.progress {
                Gauge(value: Double(progress), in: 0...100) {
                    Text(goal.title)
                } currentValueLabel: {
                    Text("\(progress)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(NorthColor.signal)
                .scaleEffect(0.7)
                .frame(width: 40, height: 40)
            } else if goal.milestoneTotal > 0 {
                Text("\(goal.milestoneDone)/\(goal.milestoneTotal)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

private struct TimelineRow: View {
    let entry: TodayTimelineEntry

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: symbol, tint: .secondary)
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.north(.body).weight(.medium))
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.north(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.at, style: .time)
                .font(.north(.subheadline).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// The web sends its own icon names; the kind is steadier to map.
    private var symbol: String {
        let kind = entry.kind.lowercased()
        let symbols: [(String, String)] = [
            ("check", "checkmark.circle"), ("workout", "figure.run"), ("activity", "figure.run"),
            ("session", "figure.run"), ("meal", "fork.knife"), ("food", "fork.knife"),
            ("nutrition", "fork.knife"), ("water", "drop"), ("hydration", "drop"), ("sleep", "moon"),
            ("goal", "target"), ("milestone", "target"), ("memory", "brain"),
            ("decision", "arrow.triangle.branch"), ("mood", "face.smiling"), ("journal", "book"),
        ]
        return symbols.first { kind.contains($0.0) }?.1 ?? "clock"
    }
}
