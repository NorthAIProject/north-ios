import Foundation
import Testing
@testable import khepri

/// Asserts `emblem-motion.fixtures.json`, the numbers the web's
/// emblem-motion.test.ts asserts too (copied from north-web-app `design/`).
@Suite struct EmblemMotionTests {
    struct Fixtures: Decodable {
        struct Ease: Decodable { let easing: EmblemMotion.Easing; let x: Double; let expect: Double }
        struct Track: Decodable { let track: Int; let seconds: Double; let expect: Double }
        struct Entrance: Decodable { let seconds: Double; let translateY: Double; let rotateYDegrees: Double }
        struct Tilt: Decodable { let x: Double; let y: Double; let yawDegrees: Double; let pitchDegrees: Double }
        struct Approach: Decodable { let current: Double; let target: Double; let dt: Double; let tau: Double; let expect: Double }

        let ease: [Ease]
        let track: [Track]
        let entrance: [Entrance]
        let tilt: [Tilt]
        let approach: [Approach]
    }

    private final class Marker {}

    let motion: EmblemMotion
    let fixtures: Fixtures

    init() throws {
        motion = try EmblemMotion.load()
        let url = try #require(Bundle(for: Marker.self).url(forResource: "emblem-motion.fixtures", withExtension: "json"))
        fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    private func near(_ actual: Double, _ expected: Double, _ what: String) {
        #expect(abs(actual - expected) < 1e-6, "\(what): \(actual) != \(expected)")
    }

    @Test func ease() {
        for c in fixtures.ease { near(EmblemMotion.ease(c.easing, c.x), c.expect, "ease \(c.easing)(\(c.x))") }
    }

    @Test func tracks() {
        for c in fixtures.track { near(motion.idle[c.track].value(at: c.seconds), c.expect, "track \(c.track) at \(c.seconds)") }
    }

    @Test func entrance() {
        for c in fixtures.entrance {
            let got = motion.entrance.offsets(at: c.seconds)
            near(got.translateY, c.translateY, "entrance y at \(c.seconds)")
            near(got.rotateYDegrees, c.rotateYDegrees, "entrance yaw at \(c.seconds)")
        }
    }

    @Test func tilt() {
        for c in fixtures.tilt {
            let got = motion.pointer.tilt(x: c.x, y: c.y)
            near(got.yawDegrees, c.yawDegrees, "yaw (\(c.x), \(c.y))")
            near(got.pitchDegrees, c.pitchDegrees, "pitch (\(c.x), \(c.y))")
        }
    }

    @Test func approach() {
        for c in fixtures.approach {
            near(EmblemMotion.approach(c.current, c.target, dt: c.dt, tau: c.tau), c.expect, "approach \(c.current)→\(c.target)")
        }
    }

    @Test func namedTracksExist() {
        #expect(motion.sunPulse != nil)
        #expect(motion.lightSweep != nil)
    }
}
