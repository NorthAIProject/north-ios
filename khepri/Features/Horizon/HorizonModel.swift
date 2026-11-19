import Foundation
import NorthAPI

/// The forecast as the screens read it: the response's own types, flattened
/// where the generated ones nest, and nothing worked out here. Every number
/// and every sentence is the server's.
nonisolated struct HorizonSeries: Equatable, Sendable, Identifiable {
    struct Point: Equatable, Sendable {
        let offsetDays: Int
        let low: Double
        let mid: Double
        let high: Double
    }

    let id: String
    let name: String
    /// "kg" or "cm".
    let unit: String
    let isReady: Bool
    let now: Double?
    let points: [Point]
    /// What is missing, when not ready; already worded.
    let needs: [String]
    /// "Would have landed in range 7 of 9 times", when there is a record.
    let trackRecord: String?
    /// A lift's state in words ("Plateau"); nil for weight and waist.
    let note: String?
    /// A line under the row: the target weight's arrival, for weight.
    var footnote: String?
    /// What the number is, when the name alone would mislead: a lift's row
    /// is its estimated max, not the weight on the bar.
    var measure: String?

    func point(at offsetDays: Int) -> Point? {
        points.first { $0.offsetDays == offsetDays }
    }

    /// The furthest day ahead this is forecast to.
    var reach: Int { points.last?.offsetDays ?? 0 }

    /// Where a day's range sits on a track spanning everything the series
    /// is forecast to do, each 0 to 1, so the bar moves and widens as the
    /// day changes. Nil without a point for the day.
    func bar(at offsetDays: Int) -> HorizonBar? {
        guard let point = point(at: offsetDays), let now else { return nil }
        var low = now, high = now
        for other in points {
            low = min(low, other.low)
            high = max(high, other.high)
        }
        // A flat series still needs a track to sit on.
        let pad = max((high - low) * 0.08, abs(now) * 0.005, 0.1)
        low -= pad
        high += pad
        let span = high - low
        return HorizonBar(
            low: (point.low - low) / span,
            mid: (point.mid - low) / span,
            high: (point.high - low) / span,
            now: (now - low) / span
        )
    }
}

nonisolated struct HorizonBar: Equatable, Sendable {
    let low: Double
    let mid: Double
    let high: Double
    let now: Double
}

nonisolated struct HorizonFrame: Equatable, Sendable {
    let offsetDays: Int
    let date: Date
    let shape: BodyShape
    /// Region → fatigue, 0 to 1: what the figure draws.
    let heat: [String: Double]
    /// Regions gone untrained for over two weeks, longest first.
    let detrained: [String]
}

nonisolated struct HorizonScenario: Equatable, Sendable {
    static let maxSkipWeeks = 4

    var skipWeeks = 0
    var extraSession = false
    var deloadNow = false

    var isPlain: Bool { self == HorizonScenario() }
}

nonisolated struct HorizonForecast: Equatable, Sendable {
    let isReady: Bool
    let scenario: HorizonScenario
    /// What is missing before anything can be forecast.
    let needs: [Need]
    let summary: [String]
    let disclaimer: String
    let hasPlan: Bool
    let frames: [HorizonFrame]
    /// Lifts first, then weight, then waist.
    let series: [HorizonSeries]
    /// Why a lighter week is worth considering; empty when it is not.
    let deloadReasons: [String]

    struct Need: Equatable, Sendable, Identifiable {
        let id: String
        let text: String
        let have: Int
        let want: Int
    }

    init(_ response: Components.Schemas.Horizon, weightName: String, waistName: String, liftMeasure: String) {
        isReady = response.status == "ready"
        scenario = HorizonScenario(
            skipWeeks: response.scenario.skipWeeks,
            extraSession: response.scenario.extraSessions > 0,
            deloadNow: response.scenario.deloadNow
        )
        needs = response.needs.enumerated().map { index, need in
            Need(id: "\(index)-\(need.code)", text: need.text, have: need.have, want: need.want)
        }
        summary = response.summary
        disclaimer = response.disclaimer
        hasPlan = response.hasPlan
        frames = response.frames.map(HorizonFrame.init)
        var all = response.lifts.map { lift in
            var series = HorizonSeries(
                lift.value1, id: "lift:" + lift.value2.key, name: lift.value2.name, note: lift.value2.plateauText
            )
            series.measure = liftMeasure
            return series
        }
        var weight = HorizonSeries(response.bodyWeight, id: "weight", name: weightName, note: nil)
        weight.footnote = response.goalEta?.text
        all.append(weight)
        all.append(HorizonSeries(response.waist, id: "waist", name: waistName, note: nil))
        series = all
        deloadReasons = response.deload.suggested ? response.deload.reasons.map(\.text) : []
    }
}

nonisolated extension HorizonSeries {
    init(_ series: Components.Schemas.HorizonSeries, id: String, name: String, note: String?) {
        self.id = id
        self.name = name
        unit = series.unit
        isReady = series.status == "ready"
        now = series.now
        points = series.points.map { Point(offsetDays: $0.offsetDays, low: $0.low, mid: $0.mid, high: $0.high) }
        needs = series.needs.map(\.text)
        trackRecord = series.trackRecord?.text
        self.note = isReady ? note : nil
        footnote = nil
        measure = nil
    }
}

nonisolated extension HorizonFrame {
    private static let dayFormat: Date.ISO8601FormatStyle = .iso8601.year().month().day()

    init(_ frame: Components.Schemas.HorizonFrame) {
        offsetDays = frame.offsetDays
        // The server's calendar date; noon keeps it on its day in any zone.
        let day = (try? Self.dayFormat.parse(frame.date)) ?? .now
        date = day.addingTimeInterval(12 * 3600)
        shape = BodyShape(
            waist: Float(frame.shape.waist), hips: Float(frame.shape.hips),
            chest: Float(frame.shape.chest), overall: Float(frame.shape.overall)
        )
        heat = Dictionary(frame.regions.map { ($0.id, $0.fatigue) }, uniquingKeysWith: max)
        detrained = frame.regions
            .filter { $0.retained < 0.995 }
            .sorted { $0.retained < $1.retained }
            .map(\.id)
    }
}
