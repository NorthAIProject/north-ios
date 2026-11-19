import Foundation
import NorthAPI
import Testing

@testable import khepri

/// A forecast as the API sends it, small enough to read: one lift forecast
/// four weeks out, a weight forecast one week out, no waist yet.
private func response(skipWeeks: Int = 0, squatHigh: Double = 146) throws -> Components.Schemas.Horizon {
    let json = """
    {
      "status": "ready", "generatedAt": "2026-11-18T12:00:00Z",
      "scenario": {"skipWeeks": \(skipWeeks), "extraSessions": 0, "deloadNow": false},
      "needs": [], "summary": ["Barbell Squat, est. 1RM: 139.7 to 142.5 kg in 4 weeks"],
      "disclaimer": "A range, not a promise.", "hasPlan": true,
      "frames": [
        {"offsetDays": 0, "date": "2026-11-18", "shape": {"waist": 0.1, "hips": 0, "chest": 0, "overall": 0.05},
         "regions": [{"id": "quads", "fatigue": 0.4, "retained": 1}]},
        {"offsetDays": 28, "date": "2026-12-16", "shape": {"waist": 0.05, "hips": 0, "chest": 0, "overall": 0},
         "regions": [{"id": "quads", "fatigue": 0.1, "retained": 1}, {"id": "chest", "fatigue": 0, "retained": 0.8},
                     {"id": "erectors", "fatigue": 0, "retained": 0.6}]}
      ],
      "lifts": [{
        "key": "barbell-squat", "name": "Barbell Squat", "slug": "barbell-squat", "status": "ready", "unit": "kg",
        "needs": [], "now": 140,
        "points": [{"offsetDays": 0, "low": 140, "mid": 140, "high": 140},
                   {"offsetDays": 7, "low": 139, "mid": 140.5, "high": 142},
                   {"offsetDays": 28, "low": 138, "mid": 142, "high": \(squatHigh)}],
        "plateau": "progressing", "plateauText": "Progressing",
        "trackRecord": {"horizonWeeks": 4, "hits": 5, "total": 6, "kind": "backtest",
                        "text": "Would have landed in range 5 of 6 times"}
      }],
      "bodyWeight": {"status": "ready", "unit": "kg", "needs": [], "now": 80,
                     "points": [{"offsetDays": 0, "low": 80, "mid": 80, "high": 80},
                                {"offsetDays": 7, "low": 79.2, "mid": 79.6, "high": 80.1}]},
      "waist": {"status": "insufficient", "unit": "cm", "points": [],
                "needs": [{"code": "waist_checks", "have": 1, "want": 3, "text": "1 of 3 waist measurements"}]},
      "goalEta": {"targetKg": 78, "state": "open", "text": "Target weight from 9 December at the earliest"},
      "deload": {"suggested": false, "reasons": [{"code": "long_since_lighter_week", "text": "Six weeks without a lighter week"}]}
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(Components.Schemas.Horizon.self, from: Data(json.utf8))
}

/// One lift's detail as the API sends it: a long history, the forecast, two
/// earlier forecasts and, when asked for, a form check.
private func liftResponse(formNote: String = "") throws -> Components.Schemas.HorizonLiftDetail {
    let json = """
    {
      "key": "barbell-squat", "name": "Barbell Squat", "slug": "barbell-squat", "status": "ready", "unit": "kg",
      "needs": [], "now": 140,
      "points": [{"offsetDays": 0, "low": 140, "mid": 140, "high": 140},
                 {"offsetDays": 28, "low": 138, "mid": 142, "high": 146}],
      "plateau": "progressing", "plateauText": "Progressing",
      "history": [{"date": "2026-11-15", "value": 140}, {"date": "2025-12-01", "value": 100},
                  {"date": "2026-10-01", "value": 132}],
      "past": [{"madeOn": "2026-09-24", "predicted": 134.4, "actual": 138.8},
               {"madeOn": "2026-10-22", "predicted": 145.2, "actual": 144.9}]\(formNote)
    }
    """
    return try JSONDecoder().decode(Components.Schemas.HorizonLiftDetail.self, from: Data(json.utf8))
}

private let filmed = """
,
      "formNote": {"analysisId": "a1", "date": "2026-11-16", "summary": "Depth is good.", "confidence": "medium",
                   "cue": "Knees out."}
"""

struct HorizonLiftDetailTests {
    private let today = Date(timeIntervalSince1970: 1_795_089_600) // 2026-11-19 12:00 UTC

    @Test func readsHistoryOldestFirstAndEarlierForecastsNewestFirst() throws {
        let detail = HorizonLiftDetail(try liftResponse(), measure: "Est. 1RM")
        #expect(detail.series.name == "Barbell Squat" && detail.series.measure == "Est. 1RM")
        #expect(detail.history.map(\.value) == [100, 132, 140])
        #expect(detail.past.map(\.predicted) == [145.2, 134.4])
    }

    /// Nobody has filmed the lift: the response has no form note at all, and
    /// that is every person today.
    @Test func aLiftNobodyFilmedHasNoFormNote() throws {
        #expect(HorizonLiftDetail(try liftResponse(), measure: "").formNote == nil)
    }

    @Test func carriesTheLastFormCheck() throws {
        let note = try #require(HorizonLiftDetail(try liftResponse(formNote: filmed), measure: "").formNote)
        #expect(note.summary == "Depth is good." && note.cue == "Knees out." && note.analysisID == "a1")
    }

    /// A confidence this build has never heard of reads as the cautious one.
    @Test func anUnknownConfidenceReadsAsLow() {
        #expect(HorizonLiftDetailView.confidenceText("certain") == HorizonLiftDetailView.confidenceText("low"))
        #expect(HorizonLiftDetailView.confidenceText("high") != HorizonLiftDetailView.confidenceText("low"))
    }

    /// A year-old set would squeeze a four-week range into the chart's corner.
    @Test func theChartLeavesOutALongPast() throws {
        let detail = HorizonLiftDetail(try liftResponse(), measure: "")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(detail.recent(from: today, calendar: calendar).map(\.value) == [132, 140])
        let ahead = detail.ahead(from: today, calendar: calendar)
        #expect(ahead.count == 2 && ahead.last?.point.high == 146)
        #expect(ahead.last.map { calendar.dateComponents([.day], from: today, to: $0.date).day } == 28)
    }

    @Test func onlyLiftRowsOpenADetail() throws {
        let model = forecast(try response())
        let routes = model.series.map(HorizonLiftRoute.init)
        #expect(routes.map { $0?.key } == ["barbell-squat", nil, nil])
    }
}

struct HorizonShareCardTests {
    /// Lifts only, as ranges with their track record. Body weight is ready
    /// in this forecast and still stays off the picture.
    @Test func sharesLiftsOnlyAsRangesWithTheirRecord() throws {
        let rows = HorizonShareCard.rows(forecast(try response()))
        #expect(rows.map(\.name) == ["Barbell Squat"])
        #expect(rows.map(\.weeks) == [4])
        #expect(rows.allSatisfy { $0.range.contains("–") })
        #expect(rows.first?.record == "Would have landed in range 5 of 6 times")
    }

    /// A what-if is not a forecast, so it is never the picture that gets shared.
    @MainActor @Test func aWhatIfIsNotShared() throws {
        #expect(HorizonShareCard.render(forecast(try response(skipWeeks: 2))) == nil)
        #expect(HorizonShareCard.render(forecast(try response())) != nil)
    }
}

private func forecast(_ response: Components.Schemas.Horizon) -> HorizonForecast {
    HorizonForecast(response, weightName: "Body weight", waistName: "Waist", liftMeasure: "Est. 1RM")
}

struct HorizonModelTests {
    @Test func listsLiftsThenWeightThenWaist() throws {
        let model = forecast(try response())
        #expect(model.isReady && model.hasPlan && model.scenario.isPlain)
        #expect(model.series.map(\.id) == ["lift:barbell-squat", "weight", "waist"])
        #expect(model.series.map(\.name) == ["Barbell Squat", "Body weight", "Waist"])
    }

    /// A lift's number is its estimated max, and the row says so; a weight is a weight.
    @Test func onlyLiftsCarryTheMeasureLabel() throws {
        let model = forecast(try response())
        #expect(model.series.map(\.measure) == ["Est. 1RM", nil, nil])
        #expect(model.series[0].note == "Progressing")
        #expect(model.series[0].trackRecord == "Would have landed in range 5 of 6 times")
        #expect(model.series[1].footnote == "Target weight from 9 December at the earliest")
    }

    @Test func aSeriesNotReadySaysWhatIsMissing() throws {
        let waist = forecast(try response()).series[2]
        #expect(!waist.isReady && waist.needs == ["1 of 3 waist measurements"])
        #expect(waist.bar(at: 0) == nil && waist.point(at: 0) == nil)
    }

    /// The figure is painted by muscle key, which is what a frame's regions are keyed by.
    @Test func framesPaintTheFigureByMuscleKey() throws {
        let frames = forecast(try response()).frames
        #expect(frames[0].heat == ["quads": 0.4])
        #expect(frames[0].detrained.isEmpty)
        #expect(Set(frames[1].heat.keys).isSubset(of: Set(BodyMapText.names.keys)))
        // Longest untrained first.
        #expect(frames[1].detrained == ["erectors", "chest"])
        #expect(frames[1].shape == BodyShape(waist: 0.05))
        let day = Calendar.current.dateComponents([.month, .day], from: frames[1].date)
        #expect(day.month == 12 && day.day == 16)
    }

    @Test func aDeloadIsOnlyShownWhenSuggested() throws {
        #expect(forecast(try response()).deloadReasons.isEmpty)
    }

    /// The bar sits inside its track on every day, starts as a point on
    /// today's mark, and widens as the day moves out.
    @Test func theBarWidensAsTheDayMovesOut() throws {
        let squat = forecast(try response()).series[0]
        let today = try #require(squat.bar(at: 0))
        let week = try #require(squat.bar(at: 7))
        let month = try #require(squat.bar(at: 28))
        #expect(today.low == today.high && today.low == today.now)
        #expect(week.high - week.low < month.high - month.low)
        for bar in [today, week, month] {
            #expect(bar.low >= 0 && bar.high <= 1 && bar.low <= bar.mid && bar.mid <= bar.high)
            #expect(bar.now == today.now, "today's mark does not move while scrubbing")
        }
    }

    /// A series is never drawn further ahead than it was forecast.
    @Test func aDayPastTheForecastHasNoBar() throws {
        let weight = forecast(try response()).series[1]
        #expect(weight.reach == 7)
        #expect(weight.bar(at: 28) == nil)
    }
}

/// Answers in the order the test releases them, to stage a slow first reply.
private actor StagedForecasts: HorizonServicing {
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var asked: [Int] = []
    var failing = false

    func forecast(_ scenario: HorizonScenario) async throws -> Components.Schemas.Horizon {
        asked.append(scenario.skipWeeks)
        if scenario.skipWeeks == 1 {
            await withCheckedContinuation { waiting[1] = $0 }
        }
        if failing { throw URLError(.notConnectedToInternet) }
        return try response(skipWeeks: scenario.skipWeeks, squatHigh: 146 - Double(scenario.skipWeeks))
    }

    func lift(_ key: String) async throws -> Components.Schemas.HorizonLiftDetail {
        try liftResponse()
    }

    func release(_ skipWeeks: Int) {
        waiting.removeValue(forKey: skipWeeks)?.resume()
    }

    func fail() { failing = true }
}

@MainActor
struct HorizonStoreTests {
    private func settle(_ store: HorizonStore, until done: @MainActor () -> Bool) async {
        for _ in 0..<200 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aWhatIfKeepsTheDayBeingLookedAt() async {
        let store = HorizonStore(service: StagedForecasts())
        await store.load()
        store.frameIndex = 1
        store.set { $0.skipWeeks = 2 }
        await settle(store) { store.forecast?.scenario.skipWeeks == 2 }
        #expect(store.forecast?.scenario.skipWeeks == 2)
        #expect(store.frameIndex == 1 && store.offsetDays == 28)
        #expect(!store.isLoading)
    }

    @Test func timeOffIsKeptWithinFourWeeks() async {
        let service = StagedForecasts()
        let store = HorizonStore(service: service)
        store.set { $0.skipWeeks = 9 }
        await settle(store) { store.forecast != nil }
        #expect(store.scenario.skipWeeks == HorizonScenario.maxSkipWeeks)
        store.set { $0.skipWeeks = -3 }
        await settle(store) { store.forecast?.scenario.skipWeeks == 0 }
        #expect(store.scenario.skipWeeks == 0)
        #expect(await service.asked == [4, 0])
    }

    /// One week off is slow to answer; three weeks is tapped meanwhile. The
    /// late answer for one week must not replace what is on screen.
    @Test func aSlowAnswerForAnOlderTapIsDropped() async {
        let service = StagedForecasts()
        let store = HorizonStore(service: service)
        store.set { $0.skipWeeks = 1 }
        store.set { $0.skipWeeks = 3 }
        await settle(store) { store.forecast?.scenario.skipWeeks == 3 }
        await service.release(1)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.forecast?.scenario.skipWeeks == 3)
        #expect(store.scenario.skipWeeks == 3 && !store.isLoading)
    }

    @Test func aFailedLoadSaysSoAndKeepsNothingStale() async {
        let service = StagedForecasts()
        await service.fail()
        let store = HorizonStore(service: service)
        await store.load()
        #expect(store.forecast == nil && store.failure != nil && !store.isLoading)
    }

    @Test func changingNothingAsksNothing() async {
        let service = StagedForecasts()
        let store = HorizonStore(service: service)
        store.set { $0.skipWeeks = 0 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await service.asked.isEmpty)
    }
}
