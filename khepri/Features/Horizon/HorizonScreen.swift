import NorthKit
import SwiftUI

/// Horizon: where training is heading. The body figure on top, the day being
/// looked at directly below it, then every forecast as a range on that day.
/// Scrubbing changes the figure and every bar together; nothing here is a
/// single number once it is about the future.
struct HorizonScreen: View {
    @State private var store = HorizonStore()
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Horizon")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    if let picture = shareImage.map(Image.init(uiImage:)) {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: picture, preview: SharePreview("Where this is heading", image: picture)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .navigationDestination(for: HorizonLiftRoute.self) { route in
                    HorizonLiftDetailScreen(key: route.key, name: route.name)
                }
                .task { await store.load() }
                // Only the plain forecast is shared: a what-if is not a forecast.
                .onChange(of: store.forecast, initial: true) { _, latest in
                    shareImage = latest.flatMap(HorizonShareCard.render)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let forecast = store.forecast {
            if forecast.isReady {
                HorizonForecastView(store: store, forecast: forecast)
            } else {
                HorizonLowData(forecast: forecast, heat: store.frame?.heat ?? [:], shape: store.frame?.shape ?? .modelled)
            }
        } else if let failure = store.failure {
            ContentUnavailableView {
                Label("Could Not Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { Task { await store.load() } }
            }
        } else {
            ProgressView()
        }
    }
}

private struct HorizonForecastView: View {
    @Bindable var store: HorizonStore
    let forecast: HorizonForecast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    BodyMapView(heat: store.frame?.heat ?? [:], shape: store.frame?.shape ?? .modelled)
                        .frame(height: 320)
                        .accessibilityLabel(Text("Your body on the chosen day"))
                    Text(figureNote)
                        .font(.north(.caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 32)
                    // Below the figure, never over it: the figure owns the
                    // sideways drag, for turning it round.
                    HorizonScrubber(frames: forecast.frames, index: $store.frameIndex)
                }

                if !forecast.summary.isEmpty, forecast.scenario.isPlain {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(forecast.summary, id: \.self) { line in
                            Text(line).font(.north(.subheadline)).foregroundStyle(NorthColor.agent)
                        }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(NorthColor.agent.opacity(0.4)).frame(width: 2)
                    }
                    .accessibilityElement(children: .combine)
                }

                VStack(spacing: 0) {
                    ForEach(forecast.series) { series in
                        if let route = HorizonLiftRoute(series) {
                            NavigationLink(value: route) {
                                HStack(spacing: 8) {
                                    HorizonRangeBar(series: series, offsetDays: store.offsetDays)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Shows this lift's history and forecast"))
                        } else {
                            HorizonRangeBar(series: series, offsetDays: store.offsetDays)
                        }
                        if series.id != forecast.series.last?.id {
                            Divider().overlay(NorthColor.hairline)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: NorthRadius.large, style: .continuous).strokeBorder(NorthColor.hairline)
                }

                if !forecast.deloadReasons.isEmpty {
                    HorizonCard {
                        Text("A lighter week is worth considering").font(.north(.subheadline).weight(.medium))
                        ForEach(forecast.deloadReasons, id: \.self) { reason in
                            Label(reason, systemImage: "circle.fill")
                                .labelStyle(HorizonBulletStyle())
                                .font(.north(.subheadline))
                                .foregroundStyle(.secondary)
                        }
                        Text("Set it in your weekly review. Nothing changes unless you do.")
                            .font(.north(.footnote))
                            .foregroundStyle(.secondary)
                    }
                }

                HorizonCard {
                    HorizonWhatIfBar(store: store, hasPlan: forecast.hasPlan)
                }

                Text(forecast.disclaimer)
                    .font(.north(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(NorthColor.background)
        .overlay(alignment: .top) {
            if store.isLoading {
                ProgressView().padding(8).background(.thinMaterial, in: .capsule).padding(.top, 8)
            }
        }
    }

    private var figureNote: String {
        if !forecast.hasPlan {
            return String(localized: "You follow no plan, so this shows training stopping.")
        }
        if let lost = store.frame?.detrained, !lost.isEmpty {
            let names = lost.prefix(3).map { BodyMapText.name($0) }.formatted(.list(type: .and, width: .narrow))
            return String(localized: "Untrained for over two weeks by then: \(names)")
        }
        return String(localized: "How tired each muscle would be that morning, if you follow your plan.")
    }
}

/// A lift's row opens its detail; weight and waist have none.
struct HorizonLiftRoute: Hashable {
    let key: String
    let name: String

    init?(_ series: HorizonSeries) {
        guard series.id.hasPrefix("lift:") else { return nil }
        key = String(series.id.dropFirst("lift:".count))
        name = series.name
    }
}

/// A card on the page's surface.
private struct HorizonCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NorthRadius.large, style: .continuous).strokeBorder(NorthColor.hairline)
            }
    }
}

private struct HorizonBulletStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.font(.system(size: 4)).foregroundStyle(.tertiary)
            configuration.title
        }
    }
}

/// The day being looked at, today to twelve weeks on.
///
/// A native slider over the forecast's own days (daily for a fortnight, then
/// weekly), so there is no position between two frames, VoiceOver adjusts it
/// a step at a time, and each step is felt. The one gold thing on the page.
struct HorizonScrubber: View {
    let frames: [HorizonFrame]
    @Binding var index: Int

    private var last: Int { max(frames.count - 1, 1) }
    private var frame: HorizonFrame? { frames.indices.contains(index) ? frames[index] : frames.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.label(for: frame))
                    .font(.north(.title3).weight(.medium))
                    .contentTransition(.numericText())
                Spacer()
                if index > 0 {
                    Button("Back to Today") { index = 0 }
                        .font(.north(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Slider(
                value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                in: 0...Double(last),
                step: 1
            )
            .tint(NorthColor.signal)
            .accessibilityLabel(Text("Day to look at"))
            .accessibilityValue(Text(Self.label(for: frame)))
            .sensoryFeedback(.selection, trigger: index)
            HStack {
                Text("Today")
                Spacer()
                Text("12 wk")
            }
            .font(.northMono(.caption2))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    static func label(for frame: HorizonFrame?) -> String {
        guard let frame, frame.offsetDays > 0 else { return String(localized: "Today") }
        let day = frame.date.formatted(.dateTime.day().month(.wide))
        if frame.offsetDays % 7 == 0 {
            return String(localized: "In \(frame.offsetDays / 7) weeks, \(day)")
        }
        return String(localized: "In \(frame.offsetDays) days, \(day)")
    }
}

/// One forecast number on the day being looked at: a low-to-high bar with a
/// soft tick at its middle, never a dot, and a thin mark where today's level
/// is for the eye to measure against.
struct HorizonRangeBar: View {
    let series: HorizonSeries
    let offsetDays: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(series.name).font(.north(.subheadline).weight(.medium)).lineLimit(1)
                if let note = series.note {
                    Text(note).font(.north(.caption)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let text = rangeText {
                    if let measure = series.measure {
                        Text(measure).font(.north(.caption)).foregroundStyle(.secondary)
                    }
                    Text(text).font(.north(.subheadline).monospacedDigit())
                }
            }

            if !series.isReady {
                ForEach(series.needs, id: \.self) { need in
                    Text(need).font(.north(.caption)).foregroundStyle(.secondary)
                }
            } else if let bar = series.bar(at: offsetDays) {
                track(bar)
            } else {
                Text("Forecast only \(max(series.reach / 7, 1)) weeks out so far: it never reaches further ahead than your history is long.")
                    .font(.north(.caption))
                    .foregroundStyle(.secondary)
            }

            if let record = series.trackRecord {
                Text(record).font(.north(.caption)).foregroundStyle(.secondary)
            }
            if let footnote = series.footnote {
                Text(footnote).font(.north(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var rangeText: String? {
        guard series.isReady, let point = series.point(at: offsetDays) else { return nil }
        let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        if offsetDays == 0 {
            return "\(point.mid.formatted(number)) \(series.unit)"
        }
        return "\(point.low.formatted(number))–\(point.high.formatted(number)) \(series.unit)"
    }

    private func track(_ bar: HorizonBar) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(NorthColor.hairline).frame(height: 1)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1, height: 12)
                    .offset(x: width * bar.now)
                Capsule()
                    .fill(.primary.opacity(0.85))
                    // Never thinner than its own height, or today's
                    // zero-width range vanishes.
                    .frame(width: max(width * (bar.high - bar.low), 8), height: 8)
                    .offset(x: width * bar.low)
                if offsetDays > 0 {
                    Capsule()
                        .fill(NorthColor.surface)
                        .frame(width: 2, height: 8)
                        .offset(x: width * bar.mid - 1)
                }
            }
            .frame(height: 12)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: bar)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

/// The what-ifs. They move readiness, detraining and timing; nothing here
/// claims that training more makes anyone stronger, and the copy says so.
struct HorizonWhatIfBar: View {
    let store: HorizonStore
    let hasPlan: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("What if").font(.north(.subheadline).weight(.medium))
                Spacer()
                if !store.scenario.isPlain {
                    Button("Plain Forecast") { store.set { $0 = HorizonScenario() } }
                        .font(.north(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            Text("I take time off, starting today").font(.north(.caption)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...HorizonScenario.maxSkipWeeks, id: \.self) { weeks in
                    chip(Text("\(weeks) wk off"), isOn: store.scenario.skipWeeks == weeks) {
                        store.set { $0.skipWeeks = $0.skipWeeks == weeks ? 0 : weeks }
                    }
                }
            }
            if hasPlan {
                HStack(spacing: 6) {
                    chip(Text("A lighter week now"), isOn: store.scenario.deloadNow) {
                        store.set { $0.deloadNow.toggle() }
                    }
                    chip(Text("One more session a week"), isOn: store.scenario.extraSession) {
                        store.set { $0.extraSession.toggle() }
                    }
                }
            }
            Text(
                store.scenario.extraSession
                    ? "An extra session changes how tired each muscle is, not the strength forecast: nothing in your logs can show that it would make you stronger."
                    : "These change how rested each muscle would be, and when your progress picks up again. Time off never raises a forecast."
            )
            .font(.north(.caption))
            .foregroundStyle(.secondary)
        }
    }

    private func chip(_ title: Text, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.north(.caption).weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(isOn ? NorthColor.background : .secondary)
                .background(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear), in: .capsule)
                .overlay { Capsule().strokeBorder(isOn ? AnyShapeStyle(.primary) : AnyShapeStyle(NorthColor.hairline)) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Too little history to forecast anything. No scrubber and no numbers: a
/// line drawn through three points would be a guess with a chart. Instead,
/// exactly what is missing, each as progress toward enough.
struct HorizonLowData: View {
    let forecast: HorizonForecast
    let heat: [String: Double]
    let shape: BodyShape

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BodyMapView(heat: heat, shape: shape)
                    .frame(height: 280)
                    .accessibilityHidden(true)
                Text("Not enough history yet").font(.north(.title3).weight(.medium))
                Text("A forecast needs a few weeks of your own numbers. Here is what is missing.")
                    .font(.north(.subheadline))
                    .foregroundStyle(.secondary)
                ForEach(forecast.needs) { need in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(need.text).font(.north(.subheadline))
                        ProgressView(value: Double(min(need.have, need.want)), total: Double(max(need.want, 1)))
                            .tint(.primary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
        }
        .background(NorthColor.background)
    }
}
