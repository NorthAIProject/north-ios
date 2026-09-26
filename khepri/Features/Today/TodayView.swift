import NorthAPI
import NorthKit
import SwiftUI

/// The day at a glance: the one next step, streak and check-in, goals, water
/// and sleep, and what happened recently.
struct TodayView: View {
    let snapshot: TodaySnapshot
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let briefing = snapshot.briefing, !briefing.isEmpty {
                    Text(briefing)
                        .font(.north(.title3))
                        .lineSpacing(2)
                }

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

                HStack(spacing: 12) {
                    Metric(title: "Streak", value: snapshot.streak, unit: snapshot.streak == 1 ? "day" : "days")
                    if snapshot.checkedInToday {
                        Metric(title: "Check-in", text: "Done")
                    } else {
                        Button { router.open(.checkInFlow) } label: {
                            Metric(title: "Check-in", text: "Open")
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Without a next step, the tour points at the day's numbers.
                .modifier(TourAnchorIf(step: .today, when: snapshot.nextStep == nil))

                TodaySection("Goals") {
                    if snapshot.goals.isEmpty {
                        Row { Text("No active goals yet.").foregroundStyle(.secondary) }
                    } else {
                        ForEach(Array(snapshot.goals.enumerated()), id: \.element.id) { index, goal in
                            if index > 0 { Divider().padding(.leading, 16) }
                            GoalRow(goal: goal)
                        }
                    }
                }

                TodaySection("Water and sleep") {
                    Row {
                        LabeledContent("Water", value: "\(snapshot.hydration.todayML) / \(snapshot.hydration.targetML) ml")
                    }
                    Divider().padding(.leading, 16)
                    Row {
                        LabeledContent("Sleep", value: snapshot.sleep.logged ? Duration.seconds(snapshot.sleep.durationMinutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) : "Not logged")
                    }
                }

                if !snapshot.timeline.isEmpty {
                    TodaySection("Recently") {
                        ForEach(Array(snapshot.timeline.enumerated()), id: \.offset) { index, entry in
                            if index > 0 { Divider().padding(.leading, 16) }
                            TimelineRow(entry: entry)
                        }
                    }
                }
                NewsSection()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
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
                .font(.north(.title2).weight(.semibold))
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(step.cta, action: action)
                .northProminentButton()
                .padding(.top, 4)
        }
        .northCard()
    }
}

private struct Metric: View {
    let title: String
    let display: Text

    init(title: String, value: Int, unit: String) {
        self.title = title
        self.display = Text(value, format: .number).font(.north(.title).weight(.light).monospacedDigit()) + Text(" \(unit)").font(.subheadline).foregroundStyle(.secondary)
    }

    init(title: String, text: String) {
        self.title = title
        self.display = Text(text).font(.north(.title).weight(.light))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .northEyebrow()
            display
                .contentTransition(.numericText())
        }
        .northCard()
    }
}

private struct GoalRow: View {
    let goal: TodayGoal

    var body: some View {
        Row {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
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
        Row {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.at, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// A titled group of rows on the system grouped background.
private struct TodaySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .northEyebrow()
                .padding(.leading, 16)
            VStack(spacing: 0) { content }
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: NorthRadius.medium))
        }
    }
}

private struct Row<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}
