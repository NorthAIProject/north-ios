import Charts
import NorthKit
import SwiftUI

/// One lift behind its forecast: what was logged as a line up to today, the
/// range ahead as a band that widens, how the method has done on this lift
/// before, and what the last form check of it said. The load is forecast;
/// how it is moved is not, so the two sit on one screen.
struct HorizonLiftDetailScreen: View {
    /// The lift's key from the forecast.
    let key: String
    let name: String
    var service: any HorizonServicing = HorizonService()

    @State private var detail: HorizonLiftDetail?
    @State private var failure: String?

    var body: some View {
        Group {
            if let detail {
                HorizonLiftDetailView(detail: detail, today: .now)
            } else if let failure {
                ContentUnavailableView {
                    Label("Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NorthColor.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            detail = HorizonLiftDetail(try await service.lift(key), measure: String(localized: "Est. 1RM"))
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct HorizonLiftDetailView: View {
    let detail: HorizonLiftDetail
    let today: Date

    private var series: HorizonSeries { detail.series }
    private static let number = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    if let note = series.note {
                        Text(note).font(.north(.subheadline)).foregroundStyle(.secondary)
                    }
                    Text(summary).font(.north(.subheadline))
                    if !series.isReady {
                        ForEach(series.needs, id: \.self) { need in
                            Text(need).font(.north(.caption)).foregroundStyle(.secondary)
                        }
                    }
                    if !detail.history.isEmpty {
                        HorizonFanChart(detail: detail, today: today)
                            .frame(height: 220)
                    }
                    if let record = series.trackRecord {
                        Text(record).font(.north(.caption)).foregroundStyle(.secondary)
                    }
                }
                .horizonCard()

                if let note = detail.formNote {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Last form check").font(.north(.subheadline).weight(.medium))
                            Spacer()
                            Text(note.date, format: .dateTime.day().month().year())
                                .font(.north(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Text(note.summary).font(.north(.subheadline))
                        if let cue = note.cue {
                            Text("Work on: \(cue)").font(.north(.subheadline))
                        }
                        Text(Self.confidenceText(note.confidence))
                            .font(.north(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .horizonCard()
                    .accessibilityElement(children: .combine)
                }

                if !detail.past.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How earlier forecasts landed").font(.north(.subheadline).weight(.medium))
                        ForEach(detail.past) { past in
                            HStack(alignment: .firstTextBaseline) {
                                Text(past.madeOn, format: .dateTime.day().month())
                                    .font(.north(.subheadline))
                                Spacer()
                                Text("Forecast \(past.predicted.formatted(Self.number)), lifted \(past.actual.formatted(Self.number))")
                                    .font(.north(.subheadline).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        Text("Each is the forecast made that day for four weeks later, beside what you then lifted.")
                            .font(.north(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .horizonCard()
                }
            }
            .padding(16)
        }
    }

    /// What was logged last, then the furthest range: never one number for
    /// the future.
    private var summary: String {
        guard let last = detail.history.last else {
            return String(localized: "Nothing logged for this lift yet.")
        }
        let day = last.date.formatted(.dateTime.day().month())
        let now = String(localized: "\(last.value.formatted(Self.number)) \(series.unit) on \(day).")
        guard series.isReady, let far = series.points.last, far.offsetDays > 0 else { return now }
        let weeks = max(far.offsetDays / 7, 1)
        let then = String(
            localized: "In \(weeks) weeks: between \(far.low.formatted(Self.number)) and \(far.high.formatted(Self.number)) \(series.unit)."
        )
        return now + " " + then
    }

    static func confidenceText(_ confidence: String) -> String {
        switch confidence {
        case "high": String(localized: "The clip showed the lift clearly.")
        case "medium": String(localized: "The clip showed most of the lift.")
        default: String(localized: "The clip did not show the lift clearly, so read this loosely.")
        }
    }
}

/// History as a line, the forecast as a band. The band is the point; its
/// middle is drawn faint so nobody reads it as a promise.
struct HorizonFanChart: View {
    let detail: HorizonLiftDetail
    let today: Date

    var body: some View {
        let logged = detail.recent(from: today)
        let ahead = detail.ahead(from: today)
        Chart {
            ForEach(ahead, id: \.date) { entry in
                AreaMark(x: .value("Day", entry.date),
                         yStart: .value("Low", entry.point.low),
                         yEnd: .value("High", entry.point.high))
                    .foregroundStyle(.primary.opacity(0.15))
                LineMark(x: .value("Day", entry.date), y: .value("Likely", entry.point.mid),
                         series: .value("Line", "forecast"))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [1, 4]))
                    .foregroundStyle(.primary.opacity(0.4))
            }
            ForEach(logged) { point in
                LineMark(x: .value("Day", point.date), y: .value("Logged", point.value),
                         series: .value("Line", "logged"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(.primary)
            }
            RuleMark(x: .value("Today", today))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .foregroundStyle(.secondary)
                .annotation(position: .bottom, alignment: .center) {
                    Text("Today").font(.northMono(.caption2)).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(detail.series.unit)
        .accessibilityChartDescriptor(HorizonFanDescriptor(detail: detail, logged: logged, ahead: ahead))
    }
}

/// The chart for VoiceOver: both lines of numbers, readable point by point.
private struct HorizonFanDescriptor: AXChartDescriptorRepresentable {
    let detail: HorizonLiftDetail
    let logged: [HorizonLiftDetail.Logged]
    let ahead: [(date: Date, point: HorizonSeries.Point)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let unit = detail.series.unit
        let values = logged.map(\.value) + ahead.flatMap { [$0.point.low, $0.point.high] }
        let dates = logged.map(\.date) + ahead.map(\.date)
        let start = dates.min() ?? .now
        let days: (Date) -> Double = { $0.timeIntervalSince(start) / 86_400 }
        let label: (Date) -> String = { $0.formatted(.dateTime.day().month()) }
        let xAxis = AXNumericDataAxisDescriptor(
            title: String(localized: "Day"),
            range: 0...max(days(dates.max() ?? start), 1),
            gridlinePositions: []
        ) { value in
            label(start.addingTimeInterval(value * 86_400))
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: detail.series.measure ?? detail.series.name,
            range: (values.min() ?? 0)...max(values.max() ?? 1, (values.min() ?? 0) + 1),
            gridlinePositions: []
        ) { value in
            "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
        }
        let line: (String, [(Date, Double)]) -> AXDataSeriesDescriptor = { name, points in
            AXDataSeriesDescriptor(name: name, isContinuous: true, dataPoints: points.map {
                AXDataPoint(x: days($0.0), y: $0.1, label: label($0.0))
            })
        }
        return AXChartDescriptor(
            title: detail.series.name,
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [
                line(String(localized: "Logged"), logged.map { ($0.date, $0.value) }),
                line(String(localized: "Forecast, low"), ahead.map { ($0.date, $0.point.low) }),
                line(String(localized: "Forecast, high"), ahead.map { ($0.date, $0.point.high) })
            ]
        )
    }
}

extension View {
    /// A card on the page's surface.
    func horizonCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NorthColor.surface, in: .rect(cornerRadius: NorthRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NorthRadius.large, style: .continuous).strokeBorder(NorthColor.hairline)
            }
    }
}
