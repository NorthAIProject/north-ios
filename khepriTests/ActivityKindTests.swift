import Foundation
import NorthAPI
import Testing
@testable import khepri

struct ActivityKindTests {
    private func best(_ unit: String, _ value: Double) -> Components.Schemas.StatsBest {
        .init(key: "k", label: "L", value: value, unit: unit, date: "2026-09-15")
    }

    @Test func bestsReadInTheirOwnUnits() {
        #expect(ActivityKindPage.format(best("s", 1620)) == "27:00")
        #expect(ActivityKindPage.format(best("s", 3725)) == "1:02:05")
        #expect(ActivityKindPage.format(best("km", 21.1)) == "21.1 km")
        #expect(ActivityKindPage.format(best("km/h", 26.7)) == "26.7 km/h")
        #expect(ActivityKindPage.format(best("m", 412)) == "412 m")
        #expect(ActivityKindPage.format(best("min", 75)) == "1h 15m")
    }

    @Test func aRideReadsInSpeedAndARunInPace() {
        #expect(StatsFormat.rate(measure: "speed", pace: 0, speed: 26) == "26.0 km/h")
        #expect(StatsFormat.rate(measure: "pace", pace: 341, speed: 0) == "5:41 /km")
        #expect(StatsFormat.rate(measure: nil, pace: nil, speed: nil) == nil)
    }

    @Test func aHabitNeedsAUsualDay() throws {
        let json = #"{"name":"Running","measure":"pace","sessions":4,"minutes":142,"distanceKm":25,"elevationM":0,"indoor":1,"outdoor":3,"avgPaceSeconds":341,"avgSpeedKmh":0,"avgHeartRate":156,"monthly":[],"efficiency":[],"bests":[],"usualDay":"Tuesday","usualHour":7}"#
        var kind = try JSONDecoder().decode(StatsCardioKind.self, from: Data(json.utf8))
        #expect(ActivityKindPage.habit(kind) == "Usually Tuesdays, around 7:00.")
        kind.usualDay = ""
        #expect(ActivityKindPage.habit(kind) == nil)
    }
}
