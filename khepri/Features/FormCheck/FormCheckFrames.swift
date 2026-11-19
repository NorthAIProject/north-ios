import AVFoundation
import Foundation
import UIKit

/// The stills a form check is read from, cut out of the clip on the phone.
///
/// The server reads stills, not video: the clip is kept for playback and
/// these are what the model sees. Each still is cut at an exact time, so an
/// issue the model pins to a still lands on a real frame of the clip.
nonisolated struct FormCheckStills: Sendable, Equatable {
    /// JPEG data, in clip order.
    let frames: [Data]
    /// The second of the clip each still was cut at, one per still.
    let times: [Double]
    let durationSeconds: Double
}

nonisolated enum FormCheckFrames {
    /// The server's limits (analysis.MaxFrames, media.MaxFrameEdge).
    static let maxFrames = 24
    static let maxEdge = 1024

    /// What the app sends: well inside the limits, about one still a second.
    static let targetFrames = 16
    static let frameEdge = 768
    private static let minFrames = 4
    /// Stills closer together than this show the same position twice.
    private static let minGapSeconds = 0.25
    private static let jpegQuality = 0.8

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? {
            String(localized: "Khepri could not read that clip. Try filming it again.")
        }
    }

    /// The seconds to cut stills at: evenly spread, each in the middle of
    /// its slice, so neither the first frame nor the very end is sampled.
    /// Rounded to hundredths and strictly increasing, which the server
    /// requires.
    static func times(durationSeconds: Double, target: Int = targetFrames) -> [Double] {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }
        let fit = Int(durationSeconds / minGapSeconds)
        let count = max(1, min(target, maxFrames, max(minFrames, fit)))
        var times: [Double] = []
        for index in 0..<count {
            let moment = (durationSeconds * (Double(index) + 0.5) / Double(count) * 100).rounded() / 100
            guard moment <= durationSeconds else { break }
            if let last = times.last, moment <= last { continue }
            times.append(moment)
        }
        return times
    }

    /// Cuts the stills from `video`. Throws `Failure.unreadable` when the
    /// clip has no length or no frame can be decoded.
    @concurrent
    static func stills(from video: URL) async throws -> FormCheckStills {
        let asset = AVURLAsset(url: video)
        let durationSeconds = try await asset.load(.duration).seconds
        let times = times(durationSeconds: durationSeconds)
        guard !times.isEmpty else { throw Failure.unreadable }

        let generator = AVAssetImageGenerator(asset: asset)
        // Upright as filmed, and the exact frame: the default tolerance
        // snaps to a keyframe that can be seconds away.
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: frameEdge, height: frameEdge)

        var frames: [Data] = []
        var kept: [Double] = []
        for moment in times {
            try Task.checkCancellation()
            let time = CMTime(seconds: moment, preferredTimescale: 600)
            // One frame that will not decode is skipped; its time goes too,
            // so every still sent still has its own.
            guard let image = try? await generator.image(at: time).image,
                  let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: jpegQuality)
            else { continue }
            frames.append(jpeg)
            kept.append(moment)
        }
        guard !frames.isEmpty else { throw Failure.unreadable }
        return FormCheckStills(
            frames: frames,
            times: kept,
            durationSeconds: (durationSeconds * 100).rounded() / 100
        )
    }

    /// The body's parts for one check: the clip, each still in order, one
    /// time per still, and the clip's length.
    static func parts(video: URL, stills: FormCheckStills) -> [MultipartFileBody.Part] {
        var parts: [MultipartFileBody.Part] = [
            // What the generated client labels every binary part.
            .file(field: "video", url: video, filename: video.lastPathComponent, contentType: "text/plain")
        ]
        for (index, frame) in stills.frames.enumerated() {
            let name = "frame-" + String(index + 1).leftPadded(to: 2) + ".jpg"
            parts.append(.data(field: "frames", data: frame, filename: name, contentType: "image/jpeg"))
        }
        parts.append(.text(field: "frameTimes", value: stills.times.map(Self.plain).joined(separator: ",")))
        parts.append(.text(field: "durationSeconds", value: plain(stills.durationSeconds)))
        return parts
    }

    /// A number as the server parses it: a point for the decimal mark,
    /// whatever the phone's region writes.
    static func plain(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private extension String {
    nonisolated func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
