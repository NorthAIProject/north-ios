#if DEBUG || BETA
import Foundation

/// The 3D mascot's motion: turns a time (and a pointer) into values.
///
/// Pure arithmetic over `mascot-motion.json`, a byte-for-byte copy of
/// north-web-app `design/mascot-motion.json` (`scripts/emblem-guard.sh`
/// checks it). No renderer import: `Mascot3DView` applies the values. The
/// web's `mascot-motion.ts` does the same arithmetic, and both test suites
/// assert `mascot-motion.fixtures.json`. Self-contained on purpose, so the
/// emblem experiment can be deleted without touching this.
///
/// Debug and Beta only; Release excludes this file (DESIGN.md, 3D Mascot).
struct MascotMotion: Decodable, Sendable {
    enum Easing: String, Decodable, Sendable {
        case linear, sine, easeOutCubic
    }

    struct Keyframe: Decodable, Sendable {
        let t: Double
        let v: Double
    }

    struct Track: Decodable, Sendable {
        let joint: String
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
                return a.v + (b.v - a.v) * MascotMotion.ease(easing, local)
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
            let left = 1 - MascotMotion.ease(easing, seconds / durationSeconds)
            return (from.translateY * left, from.rotateYDegrees * left)
        }
    }

    struct Blink: Decodable, Sendable {
        let joint: String
        let cycleSeconds: Double
        let startsSeconds: [Double]
        let closeSeconds: Double
        let holdSeconds: Double
        let openSeconds: Double
        let closedScaleY: Double

        /// The eyes' vertical scale: 1 open, `closedScaleY` shut. Each blink in
        /// the repeating cycle closes, holds and opens with a sine ease;
        /// overlapping blinks take the more closed value.
        func scaleY(at seconds: Double) -> Double {
            let turns = seconds / cycleSeconds
            let u = (turns - turns.rounded(.down)) * cycleSeconds
            var scale = 1.0
            for start in startsSeconds {
                let d = u - start
                if d < 0 || d >= closeSeconds + holdSeconds + openSeconds { continue }
                let v: Double
                if d < closeSeconds {
                    v = 1 - (1 - closedScaleY) * MascotMotion.ease(.sine, d / closeSeconds)
                } else if d < closeSeconds + holdSeconds {
                    v = closedScaleY
                } else {
                    v = closedScaleY + (1 - closedScaleY) * MascotMotion.ease(.sine, (d - closeSeconds - holdSeconds) / openSeconds)
                }
                scale = min(scale, v)
            }
            return scale
        }
    }

    struct Look: Equatable, Sendable {
        var headYawDegrees = 0.0
        var headPitchDegrees = 0.0
        var pupilX = 0.0
        var pupilY = 0.0

        static let rest = Look()
    }

    struct LookAt: Decodable, Sendable {
        let maxHeadYawDegrees: Double
        let maxHeadPitchDegrees: Double
        let maxPupilX: Double
        let maxPupilY: Double
        let timeConstantSeconds: Double

        /// Where the mascot looks for a pointer at (x, y), each in [-1, 1] from
        /// its centre, +y up. Pitch is negative when the pointer is above: a
        /// negative turn about X faces the mascot (+Z) up.
        func look(x: Double, y: Double) -> Look {
            let cx = min(max(x, -1), 1)
            let cy = min(max(y, -1), 1)
            return Look(
                headYawDegrees: cx * maxHeadYawDegrees,
                headPitchDegrees: -cy * maxHeadPitchDegrees,
                pupilX: cx * maxPupilX,
                pupilY: cy * maxPupilY
            )
        }
    }

    let entrance: Entrance
    let idle: [Track]
    let blink: Blink
    let lookAt: LookAt

    var hover: Track? { idle.first { $0.joint == "body" && $0.property == "translateY" } }
    var coreGlow: Track? { idle.first { $0.joint == "core" && $0.property == "emissiveScale" } }

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

    static func load(from bundle: Bundle = .main) throws -> MascotMotion {
        guard let url = bundle.url(forResource: "mascot-motion", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MascotMotion.self, from: Data(contentsOf: url))
    }
}
#endif
