import Foundation
import UIKit
import UniformTypeIdentifiers

/// A file or photo on its way to the server.
///
/// Building one decodes, shrinks and reads whole files, which is long enough
/// to stall the UI, so the builders run off the main actor.
nonisolated struct ImportFile: Equatable, Sendable {
    var filename: String
    var data: Data

    /// The largest upload the server takes.
    static let maxBytes = 10 * 1024 * 1024

    /// The longest side, in pixels, a photo is sent at.
    static let longestPhotoSide: CGFloat = 2400

    /// The kinds the server reads. Legacy .xls is offered so the server can
    /// say how to convert it, rather than the picker silently greying it out.
    static let fileTypes: [UTType] = [
        .pdf, .plainText, .commaSeparatedText, .tabSeparatedText, .json, .image,
        UTType(filenameExtension: "md"), UTType(filenameExtension: "docx"),
        UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")
    ].compactMap { $0 }

    /// A photo from the camera.
    @concurrent nonisolated static func photo(_ image: UIImage, name: String = "photo") async -> ImportFile? {
        jpeg(image, name: name)
    }

    /// A photo from the library, as the bytes the picker handed over.
    @concurrent nonisolated static func photo(data: Data, name: String = "photo") async -> ImportFile? {
        UIImage(data: data).flatMap { jpeg($0, name: name) }
    }

    /// Reads a file the person picked in Files. Images go through `jpeg` for
    /// the reason it gives.
    @concurrent nonisolated static func picked(_ url: URL) async throws -> ImportFile? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let image = UIImage(data: data) {
            return jpeg(image, name: url.deletingPathExtension().lastPathComponent)
        }
        return ImportFile(filename: url.lastPathComponent, data: data)
    }

    /// A photo becomes a JPEG no larger than it needs to be read. HEIC and
    /// WEBP are what the camera and the web produce, and not every model the
    /// server may ask can open them; a JPEG every model can.
    ///
    /// The renderer is pinned to scale 1: its default is the screen's scale,
    /// which would triple the pixels on each side instead of shrinking them.
    static func jpeg(_ image: UIImage, name: String) -> ImportFile? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let shrink = min(1, longestPhotoSide / max(pixelWidth, pixelHeight))
        let size = CGSize(width: (pixelWidth * shrink).rounded(), height: (pixelHeight * shrink).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        return ImportFile(filename: "\(name).jpg", data: data)
    }
}
