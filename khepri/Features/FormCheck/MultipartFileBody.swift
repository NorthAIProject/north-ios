import Foundation

/// A multipart/form-data body written to disk: the clip, and the stills and
/// fields that go with it.
///
/// A background URLSession uploads only from a file (`uploadTask(with:fromFile:)`),
/// so the body the generated client would stream is built here instead. The
/// file is copied in chunks, never held whole: a clip can be 90 MB (FormCheckVideo.maxBytes).
nonisolated struct MultipartFileBody: Sendable {
    let boundary: String

    init(boundary: String = "__X_KHEPRI_\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// The request's `Content-Type`.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// One part of the body.
    enum Part: Sendable {
        /// A file on disk, copied in chunks.
        case file(field: String, url: URL, filename: String, contentType: String)
        /// A small file already in memory, such as a still.
        case data(field: String, data: Data, filename: String, contentType: String)
        /// A plain text field.
        case text(field: String, value: String)
    }

    /// Writes one file as the whole body. See `write(_:to:chunkSize:)`.
    func write(
        field: String,
        file: URL,
        filename: String,
        contentType partContentType: String,
        to destination: URL,
        chunkSize: Int = 1 << 20
    ) throws {
        try write(
            [.file(field: field, url: file, filename: filename, contentType: partContentType)],
            to: destination,
            chunkSize: chunkSize
        )
    }

    /// Writes `parts` in order to `destination`, replacing anything there.
    ///
    /// A file part carries the headers the generated client gives a binary
    /// part: a form-data disposition with its parameters in name order, the
    /// part's content type, and its length.
    func write(_ parts: [Part], to destination: URL, chunkSize: Int = 1 << 20) throws {
        guard FileManager.default.createFile(atPath: destination.path(), contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path()])
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        for part in parts {
            switch part {
            case let .file(field, url, filename, contentType):
                let size = try FileManager.default.attributesOfItem(atPath: url.path())[.size] as? Int ?? 0
                try output.write(contentsOf: fileHead(field: field, filename: filename, contentType: contentType, size: size))
                try copy(url, to: output, chunkSize: chunkSize)
            case let .data(field, data, filename, contentType):
                try output.write(contentsOf: fileHead(field: field, filename: filename, contentType: contentType, size: data.count))
                try output.write(contentsOf: data)
            case let .text(field, value):
                let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\(Self.quoted(field))\r\n\r\n"
                try output.write(contentsOf: Data((head + value).utf8))
            }
            try output.write(contentsOf: Data("\r\n".utf8))
        }
        try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
    }

    private func fileHead(field: String, filename: String, contentType: String, size: Int) -> Data {
        Data((
            "--\(boundary)\r\n"
                + "Content-Disposition: form-data; filename=\(Self.quoted(filename)); name=\(Self.quoted(field))\r\n"
                + "Content-Type: \(contentType)\r\n"
                + "Content-Length: \(size)\r\n"
                + "\r\n"
        ).utf8)
    }

    private func copy(_ file: URL, to output: FileHandle, chunkSize: Int) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        var copying = true
        while copying {
            copying = try autoreleasepool {
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
                try output.write(contentsOf: chunk)
                return true
            }
        }
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
