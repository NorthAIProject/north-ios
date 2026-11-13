#if DEBUG || BETA
import Foundation

/// The 3D emblem's motion: turns a time (and a pointer) into values.
///
/// Pure arithmetic over `emblem-motion.json`, a byte-for-byte copy of
/// north-web-app `design/emblem-motion.json` (`scripts/emblem-guard.sh`
/// checks it). No renderer import: `Emblem3DView` applies the values. The
/// web's `emblem-motion.ts` does the same arithmetic, and both test suites
/// assert `emblem-motion.fixtures.json`.
///
/// Debug and Beta only; Release excludes this file (DESIGN.md, 3D Emblem).
struct EmblemMotion: Decodable, Sendable {
    enum Easing: String, Decodable, Sendable {
        case linear, sine, easeOutCubic
    }

    struct Keyframe: Decodable, Sendable {
        let t: Double
        let v: Double
    }

    struct Track: Decodable, Sendable {
        let material: String?
        let light: String?
        let property: String
        let periodSeconds: Double
        let easing: Easing
        let keyframes: [Keyframe]

        /// The looping track's value at `seconds` (negative times wrap too).
        func value(at seconds: Double) -> Double {
            let turns = seconds / periodSeconds
            let u = turns - turns.rounded(.down)
            for (a, b) in zip(keyframes, keyframes.dropFirst()) where u >= a.t && u <= b.t {
                let local = b.t > a.t ? (u - a.t) / (b.t - a.t) : 0
                return a.v + (b.v - a.v) * EmblemMotion.ease(easing, local)
            }
            return keyframes.last?.v ?? 0
        }
    }

    struct Entrance: Decodable, Sendable {
        struct From: Decodable, Sendable {
            let translateY: Double
            let rotateYDegrees: Double
        }

        let durationSeconds: Double
        let easing: Easing
        let from: From

        /// Offsets from rest during the one-shot entrance; zero once it is over.
        func offsets(at seconds: Double) -> (translateY: Double, rotateYDegrees: Double) {
            let left = 1 - EmblemMotion.ease(easing, seconds / durationSeconds)
            return (from.translateY * left, from.rotateYDegrees * left)
        }
    }

    struct Pointer: Decodable, Sendable {
        let maxYawDegrees: Double
        let maxPitchDegrees: Double
        let timeConstantSeconds: Double

        /// Target tilt toward a pointer at (x, y), each in [-1, 1] from the
        /// emblem's centre, +y up. Pitch is negative when the pointer is above:
        /// a negative turn about X faces the emblem (+Z) up.
        func tilt(x: Double, y: Double) -> (yawDegrees: Double, pitchDegrees: Double) {
            (min(max(x, -1), 1) * maxYawDegrees, -min(max(y, -1), 1) * maxPitchDegrees)
        }
    }

    let entrance: Entrance
    let idle: [Track]
    let pointer: Pointer

    var sunPulse: Track? { idle.first { $0.material == "sun_face" } }
    var lightSweep: Track? { idle.first { $0.light == "key" } }

    /// Eases x in [0, 1]; x outside is clamped.
    static func ease(_ easing: Easing, _ x: Double) -> Double {
        let u = min(max(x, 0), 1)
        switch easing {
        case .linear: return u
        case .sine: return (1 - cos(Double.pi * u)) / 2
        case .easeOutCubic: return 1 - pow(1 - u, 3)
        }
    }

    /// Exponential approach of `current` to `target` over `dt` seconds.
    static func approach(_ current: Double, _ target: Double, dt: Double, tau: Double) -> Double {
        current + (target - current) * (1 - exp(-dt / tau))
    }

    static func load(from bundle: Bundle = .main) throws -> EmblemMotion {
        guard let url = bundle.url(forResource: "emblem-motion", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(EmblemMotion.self, from: Data(contentsOf: url))
    }
}
#endif
