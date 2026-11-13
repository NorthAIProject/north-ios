import Foundation
import Testing
@testable import khepri

/// Asserts `mascot-motion.fixtures.json`, the numbers the web's
/// mascot-motion.test.ts asserts too (copied from north-web-app `design/`).
@Suite struct MascotMotionTests {
    struct Fixtures: Decodable {
        struct Ease: Decodable { let easing: MascotMotion.Easing; let x: Double; let expect: Double }
        struct Track: Decodable { let track: Int; let seconds: Double; let expect: Double }
        struct Entrance: Decodable { let seconds: Double; let translateY: Double; let rotateYDegrees: Double }
        struct Blink: Decodable { let seconds: Double; let scaleY: Double }
        struct Look: Decodable {
            let x: Double, y: Double
            let headYawDegrees: Double, headPitchDegrees: Double, pupilX: Double, pupilY: Double
        }
        struct Approach: Decodable { let current: Double; let target: Double; let dt: Double; let tau: Double; let expect: Double }

        let ease: [Ease]
        let track: [Track]
        let entrance: [Entrance]
        let blink: [Blink]
        let look: [Look]
        let approach: [Approach]
    }

    private final class Marker {}

    let motion: MascotMotion
    let fixtures: Fixtures

    init() throws {
        motion = try MascotMotion.load()
        let url = try #require(Bundle(for: Marker.self).url(forResource: "mascot-motion.fixtures", withExtension: "json"))
        fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    private func near(_ actual: Double, _ expected: Double, _ what: String) {
        #expect(abs(actual - expected) < 1e-6, "\(what): \(actual) != \(expected)")
    }

    @Test func ease() {
        for c in fixtures.ease { near(MascotMotion.ease(c.easing, c.x), c.expect, "ease \(c.easing)(\(c.x))") }
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

    @Test func blink() {
        for c in fixtures.blink { near(motion.blink.scaleY(at: c.seconds), c.scaleY, "blink at \(c.seconds)") }
    }

    @Test func look() {
        for c in fixtures.look {
            let got = motion.lookAt.look(x: c.x, y: c.y)
            near(got.headYawDegrees, c.headYawDegrees, "head yaw (\(c.x), \(c.y))")
            near(got.headPitchDegrees, c.headPitchDegrees, "head pitch (\(c.x), \(c.y))")
            near(got.pupilX, c.pupilX, "pupil x (\(c.x), \(c.y))")
            near(got.pupilY, c.pupilY, "pupil y (\(c.x), \(c.y))")
        }
    }

    @Test func approach() {
        for c in fixtures.approach {
            near(MascotMotion.approach(c.current, c.target, dt: c.dt, tau: c.tau), c.expect, "approach \(c.current)→\(c.target)")
        }
    }

    @Test func namedTracksExist() {
        #expect(motion.hover != nil)
        #expect(motion.coreGlow != nil)
        #expect(motion.blink.joint == "eyes")
    }
}
