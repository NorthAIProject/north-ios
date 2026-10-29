import AVFoundation
import Foundation

/// Keeps a picked clip under what the API takes. The server's limit
/// (media.MaxVideoBytes) sits under Cloudflare's 100 MB request-body cap on
/// kheprios.com, so a raw 4K clip from Photos would be refused before it
/// reached Khepri. A clip over the limit is re-encoded smaller; the form
/// check needs the body's lines, not every pixel.
enum FormCheckVideo {
    /// The API's media.MaxVideoBytes.
    static let maxBytes: Int64 = 90 << 20

    /// Re-encode sizes tried in order, largest first.
    private static let presets = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540]

    enum Failure: LocalizedError {
        case tooLong

        var errorDescription: String? {
            String(localized: "This clip is too long to send. Trim it to the working set and try again.")
        }
    }

    /// `video` itself when it fits, otherwise a smaller copy in the
    /// temporary directory that the caller deletes. Throws `Failure.tooLong`
    /// when even the smallest copy is over the limit.
    static func fitting(_ video: URL) async throws -> URL {
        if try size(of: video) <= maxBytes { return video }
        let asset = AVURLAsset(url: video)
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let copy = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension("mp4")
            try await session.export(to: copy, as: .mp4)
            if try size(of: copy) <= maxBytes { return copy }
            try? FileManager.default.removeItem(at: copy)
        }
        throw Failure.tooLong
    }

    private static func size(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
}
