import NorthAPI
import NorthKit
import SwiftUI

/// My Day: the vitals strip, the card grid, the body and the day's timeline.
/// Every card opens its detail in a sheet.
struct DayDashboard: View {
    let day: DayResponse
    var store: DayStore?
    @State private var detail: DayCardKind?
    @State private var editingBody = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VitalsStrip(day: day)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(DayCardKind.allCases) { kind in
                    Button { detail = kind } label: { DayCardView(kind: kind, day: day) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("day-card-\(kind.rawValue)")
                }
            }
            BodyCard(measurements: day.body) { editingBody = true }
            DayTimeline(day: day)
        }
        .sheet(item: $detail) { kind in
            NavigationStack {
                ScrollView { DayCardDetail(kind: kind, day: day, store: store).padding(16) }
                    .navigationTitle(kind.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $editingBody) {
            if let store { BodySheet(day: day, store: store) }
        }
    }
}

enum DayCardKind: String, CaseIterable, Identifiable {
    case fast, food, water, activity, sleep, workouts, nutrients, streak
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .fast: "Fasting"
        case .nutrients: "Nutrients"
        case .food: "Food"
        case .water: "Water"
        case .activity: "Activity"
        case .sleep: "Sleep"
        case .workouts: "Workouts"
        case .streak: "Streak"
        }
    }

    var symbol: String {
        switch self {
        case .fast: "timer"
        case .nutrients: "leaf"
        case .food: "fork.knife"
        case .water: "drop"
        case .activity: "waveform.path.ecg"
        case .sleep: "moon"
        case .workouts: "figure.run"
        case .streak: "flame"
        }
    }

    var color: Color {
        switch self {
        case .fast: NorthColor.Day.fat
        case .nutrients: NorthColor.Day.food
        case .food: NorthColor.Day.food
        case .water: NorthColor.Day.water
        case .activity: NorthColor.Day.move
        case .sleep: NorthColor.Day.sleep
        case .workouts: NorthColor.Day.fat
        case .streak: NorthColor.ember
        }
    }
}

// MARK: - Vitals

struct VitalsStrip: View {
    let day: DayResponse

    var body: some View {
        HStack(spacing: 6) {
            VitalTile(label: "Caffeine", value: String(day.caffeine.activeMg), unit: "mg",
                      fraction: DayMath.fraction(Double(day.caffeine.totalMg), Double(day.caffeine.limitMg)), color: NorthColor.Day.caffeine)
            VitalTile(label: "Energy", value: day.vitals.energyPercent.map(String.init), unit: "%",
                      fraction: Double(day.vitals.energyPercent ?? 0) / 100, color: NorthColor.Day.move)
            VitalTile(label: "Sunlight", value: day.vitals.daylightMinutes.map(String.init), unit: "min",
                      fraction: Double(day.vitals.daylightMinutes ?? 0) / 60, color: NorthColor.Day.sun)
            VitalTile(label: "Screen", value: day.vitals.screenMinutes.map(DayMath.duration), unit: "",
                      fraction: Double(day.vitals.screenMinutes ?? 0) / 240, color: NorthColor.Day.screen)
            if let tracker = day.milestones.first {
                VitalTile(label: LocalizedStringKey(tracker.name), value: String(tracker.monthsSince), unit: "mo",
                          fraction: tracker.fraction, color: tracker.due ? NorthColor.Day.move : NorthColor.Day.stand)
            } else {
                VitalTile(label: "Streak", value: String(day.streak), unit: "d",
                          fraction: Double(day.streak % 7) / 7, color: NorthColor.ember)
            }
        }
    }
}

private struct VitalTile: View {
    let label: LocalizedStringKey
    let value: String?
    let unit: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ArcGauge(fraction: value == nil ? 0 : fraction, color: color, lineWidth: 4)
                .frame(width: 34, height: 34)
            Group {
                if let value {
                    Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
                        + Text(" \(unit)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.subheadline.weight(.semibold))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.medium))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Cards

private struct DayCardView: View {
    let kind: DayCardKind
    let day: DayResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(kind.title, systemImage: kind.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(kind.color)
                Spacer(minLength: 4)
                Text(meta).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(minHeight: 150, alignment: .top)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large))
        .contentShape(.rect)
    }

    private var meta: String {
        switch kind {
        case .food: String(format: "%.0f kcal", day.food.calories)
        case .workouts: String(day.workouts.count)
        case .sleep: day.sleep?.quality.map { "\($0)/5" } ?? ""
        case .fast: day.fast.map { DayMath.phaseName($0.phase) } ?? ""
        case .streak: "Level \(day.level)"
        default: ""
        }
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .fast:
            if let fast = day.fast {
                ZStack {
                    RingView(fraction: fast.fraction, color: NorthColor.Day.fat, lineWidth: 7)
                    Text(DayMath.clock(fast.elapsedMinutes)).font(.title3.weight(.semibold).monospacedDigit())
                }
                .frame(width: 84, height: 84)
                .frame(maxWidth: .infinity)
            } else {
                Text("Not fasting.").font(.subheadline).foregroundStyle(.secondary)
            }
        case .nutrients:
            VStack(alignment: .leading, spacing: 4) {
                (Text(day.nutrients.covered.count, format: .number) + Text("/\(day.nutrients.total)").font(.subheadline).foregroundStyle(.secondary))
                    .font(.title.weight(.semibold).monospacedDigit())
                if !day.nutrients.missing.isEmpty {
                    Text(day.nutrients.missing.prefix(3).map(DayMath.nutrientName).joined(separator: ", "))
                        .font(.caption).foregroundStyle(NorthColor.Day.fat).lineLimit(2)
                }
            }
        case .food:
            HStack {
                MultiRingView(rings: DayMath.macroRings(day.food), lineWidth: 6)
                    .frame(width: 64, height: 64)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    MacroLine(letter: "P", grams: day.food.proteinG, color: NorthColor.Day.protein)
                    MacroLine(letter: "C", grams: day.food.carbG, color: NorthColor.Day.carb)
                    MacroLine(letter: "F", grams: day.food.fatG, color: NorthColor.Day.fat)
                }
            }
        case .water:
            HStack(alignment: .bottom) {
                VStack(alignment: .leading) {
                    Text(day.water.totalMl, format: .number).font(.title.weight(.semibold).monospacedDigit())
                    Text("ml today").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                WaterGlass(fraction: DayMath.fraction(Double(day.water.totalMl), Double(day.water.targetMl)))
                    .frame(width: 34, height: 48)
            }
        case .activity:
            HStack {
                MultiRingView(rings: DayMath.activityRings(day.activity), lineWidth: 7)
                    .frame(width: 64, height: 64)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(day.activity.move.value, format: .number.precision(.fractionLength(0))).foregroundStyle(NorthColor.Day.move)
                    Text(day.activity.exercise.value, format: .number.precision(.fractionLength(0))).foregroundStyle(NorthColor.Day.exercise)
                    Text(day.activity.stand.value, format: .number.precision(.fractionLength(0))).foregroundStyle(NorthColor.Day.stand)
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
            }
        case .sleep:
            if let sleep = day.sleep {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DayMath.duration(sleep.totalMinutes)).font(.title.weight(.semibold).monospacedDigit())
                    if !sleep.blocks.isEmpty {
                        Hypnogram(blocks: DayMath.hypnogram(sleep)).frame(height: 32)
                    }
                }
            } else {
                Text("Not logged").font(.subheadline).foregroundStyle(.secondary)
            }
        case .workouts:
            VStack(alignment: .leading, spacing: 4) {
                (Text(day.workouts.minutes, format: .number) + Text(" min").font(.subheadline).foregroundStyle(.secondary))
                    .font(.title.weight(.semibold).monospacedDigit())
                if !day.workouts.labels.isEmpty {
                    Text(day.workouts.labels.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        case .streak:
            Label { Text(day.streak, format: .number) } icon: { Image(systemName: "flame.fill") }
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .foregroundStyle(NorthColor.ember)
        }
    }
}

private struct MacroLine: View {
    let letter: String
    let grams: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(letter).font(.caption2).foregroundStyle(.secondary)
            Text(grams, format: .number.precision(.fractionLength(0))).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        }
    }
}

private struct WaterGlass: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(NorthColor.Day.water.opacity(0.15))
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(NorthColor.Day.water)
                    .frame(height: proxy.size.height * fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Details

private struct DayCardDetail: View {
    let kind: DayCardKind
    let day: DayResponse
    var store: DayStore?
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch kind {
            case .fast:
                if let fast = day.fast {
                    Text(DayMath.clock(fast.elapsedMinutes)).font(.largeTitle.weight(.semibold).monospacedDigit())
                    Text("\(DayMath.phaseName(fast.phase)) · target \(fast.targetHours)h").foregroundStyle(.secondary)
                }
                if let store {
                    if day.fast?.endedAt == nil && day.fast != nil && day.isToday {
                        Button("End the fast") { Task { await store.perform { try await $0.stopFast() } } }
                            .northProminentButton()
                    } else {
                        HStack {
                            ForEach([12, 16, 18, 24], id: \.self) { hours in
                                Button("\(hours)h") { Task { await store.perform { try await $0.startFast(hours: hours) } } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            case .nutrients:
                Text("\(day.nutrients.covered.count) of \(day.nutrients.total) tracked nutrients covered today.")
                if !day.nutrients.missing.isEmpty {
                    Text("Still missing").northEyebrow()
                    Text(day.nutrients.missing.map(DayMath.nutrientName).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            case .food:
                Grid(alignment: .leading, verticalSpacing: 8) {
                    FoodRow(label: "Energy", value: day.food.calories, goal: day.food.goal?.calories, unit: "kcal", color: .primary)
                    FoodRow(label: "Protein", value: day.food.proteinG, goal: day.food.goal?.proteinG, unit: "g", color: NorthColor.Day.protein)
                    FoodRow(label: "Carbs", value: day.food.carbG, goal: day.food.goal?.carbG, unit: "g", color: NorthColor.Day.carb)
                    FoodRow(label: "Fat", value: day.food.fatG, goal: day.food.goal?.fatG, unit: "g", color: NorthColor.Day.fat)
                }
                if day.food.goal == nil {
                    Text("Set a calorie goal in Body and goal to see how today compares.").font(.subheadline).foregroundStyle(.secondary)
                }
            case .water:
                (Text(Double(day.water.totalMl) / 1000, format: .number.precision(.fractionLength(1))) + Text(" L"))
                    .font(.largeTitle.weight(.semibold).monospacedDigit())
                Text("of \(day.water.targetMl) ml").foregroundStyle(.secondary)
            case .activity:
                Grid(alignment: .leading, verticalSpacing: 8) {
                    RingRow(label: "Move", ring: day.activity.move, unit: "kcal", color: NorthColor.Day.move)
                    RingRow(label: "Exercise", ring: day.activity.exercise, unit: "min", color: NorthColor.Day.exercise)
                    RingRow(label: "Stand", ring: day.activity.stand, unit: "h", color: NorthColor.Day.stand)
                }
            case .sleep:
                if let sleep = day.sleep {
                    Text(DayMath.duration(sleep.totalMinutes)).font(.largeTitle.weight(.semibold).monospacedDigit())
                    if let start = sleep.start, let end = sleep.end {
                        Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    if !sleep.blocks.isEmpty {
                        Hypnogram(blocks: DayMath.hypnogram(sleep)).frame(height: 64)
                        Grid(alignment: .leading, verticalSpacing: 8) {
                            ForEach(DayMath.stageOrder, id: \.self) { stage in
                                GridRow {
                                    Label(DayMath.stageName(stage), systemImage: "circle.fill")
                                        .labelStyle(StageLabelStyle(color: DayMath.stageColor(stage)))
                                    Text("\(sleep.stages.additionalProperties[stage] ?? 0) min")
                                        .foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                                }
                            }
                        }
                    }
                } else {
                    Text("No sleep recorded for last night.").foregroundStyle(.secondary)
                }
            case .workouts:
                if day.workouts.labels.isEmpty {
                    Text("No workouts on this day.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(day.workouts.labels.enumerated()), id: \.offset) { _, label in Text(label) }
                }
            case .streak:
                Text("\(day.streak) days in a row with a check-in.")
                Button("Check in") { router.open(.checkInFlow) }.northProminentButton()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StageLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 8)).foregroundStyle(color)
            configuration.title
        }
    }
}

private struct FoodRow: View {
    let label: LocalizedStringKey
    let value: Double
    let goal: Double?
    let unit: String
    let color: Color

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text("\(value, format: .number.precision(.fractionLength(0))) \(unit)").foregroundStyle(color).monospacedDigit()
            Text(goal.map { "\($0.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? "")
                .foregroundStyle(.secondary).gridColumnAlignment(.trailing)
        }
    }
}

private struct RingRow: View {
    let label: LocalizedStringKey
    let ring: DayRing
    let unit: String
    let color: Color

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text("\(ring.value, format: .number.precision(.fractionLength(0))) / \(ring.goal, format: .number.precision(.fractionLength(0))) \(unit)")
                .monospacedDigit()
            Text("\(ring.percent)%").foregroundStyle(color).gridColumnAlignment(.trailing)
        }
    }
}

// MARK: - Body and timeline

private struct BodyCard: View {
    let measurements: Components.Schemas.DayBody
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    if let weight = measurements.weightKg {
                        Chip {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(weight, format: .number.precision(.fractionLength(1))) + Text(" kg").font(.caption).foregroundStyle(.secondary)
                                if let toGoal = measurements.toGoalKg {
                                    Text("\(toGoal.formatted(.number.precision(.fractionLength(1)))) kg to goal")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let bmi = measurements.bmi {
                        Chip {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("BMI ").font(.caption).foregroundStyle(.secondary) + Text(bmi, format: .number.precision(.fractionLength(1)))
                                if let category = measurements.bmiCategory {
                                    Text(DayMath.bmiName(category)).font(.caption.weight(.medium)).foregroundStyle(DayMath.bmiColor(category))
                                }
                            }
                        }
                    }
                    if let bp = measurements.bloodPressure {
                        Chip { Text("\(bp.systolic)/\(bp.diastolic)") + Text(" mmHg").font(.caption).foregroundStyle(.secondary) }
                    }
                    if measurements.weightKg == nil {
                        Text("No weight recorded yet.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "figure.stand")
                    .font(.system(size: 110, weight: .ultraLight))
                    .foregroundStyle(NorthColor.Day.stand.opacity(0.7))
                    .accessibilityHidden(true)
            }
            if !measurements.soreness.isEmpty {
                FlowTags(tags: measurements.soreness.map { "\(DayMath.regionName($0.region)) · \(DayMath.severityName($0.severity))" })
            }
            Button("Update body", action: edit)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large))
    }
}

/// Soreness chips, wrapping onto as many lines as they need.
private struct FlowTags: View {
    let tags: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .trailing, spacing: 6) { chips }
        }
    }
    @ViewBuilder private var chips: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption.weight(.medium))
                .foregroundStyle(NorthColor.Day.move)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(NorthColor.Day.move.opacity(0.15), in: .capsule)
        }
    }
}

private struct Chip<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .font(.title3.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.background.opacity(0.8), in: .rect(cornerRadius: NorthRadius.medium))
    }
}

/// The day's timeline, latest first, with the day rules as dashed markers and
/// a "now" line on today.
struct DayTimeline: View {
    let day: DayResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Timeline").northEyebrow()
                .padding(.bottom, 8)
            if rows.isEmpty {
                Text("Nothing logged on this day yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                switch row.kind {
                case .entry(let entry):
                    HStack(spacing: 10) {
                        Circle().fill(DayMath.kindColor(entry.kind)).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.subheadline.weight(.medium)).lineLimit(1)
                            if let detail = entry.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Text(row.at, format: .dateTime.hour().minute()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                case .marker(let marker):
                    HStack(spacing: 8) {
                        Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary).frame(height: 1)
                        Text("\(marker.label) \(row.at.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .opacity(marker.passed ? 0.5 : 1)
                    .padding(.vertical, 4)
                case .now:
                    HStack(spacing: 6) {
                        Text(row.at, format: .dateTime.hour().minute())
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NorthColor.Day.now, in: .capsule)
                        Rectangle().fill(NorthColor.Day.now).frame(height: 1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large))
    }

    private var rows: [DayMath.TimelineRow] { DayMath.timeline(day) }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}
