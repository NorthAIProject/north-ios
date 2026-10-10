import Foundation

/// A multipart/form-data body holding one file, written to disk.
///
/// A background URLSession uploads only from a file (`uploadTask(with:fromFile:)`),
/// so the body the generated client would stream is built here instead. The
/// file is copied in chunks, never held whole: a clip can be 200 MB.
nonisolated struct MultipartFileBody: Sendable {
    let boundary: String

    init(boundary: String = "__X_KHEPRI_\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// The request's `Content-Type`.
    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// Writes the body to `destination`, replacing anything there.
    ///
    /// The part carries the headers the generated client gives a binary
    /// part: a form-data disposition with its parameters in name order, the
    /// part's content type, and its length.
    func write(
        field: String,
        file: URL,
        filename: String,
        contentType partContentType: String,
        to destination: URL,
        chunkSize: Int = 1 << 20
    ) throws {
        let size = try FileManager.default.attributesOfItem(atPath: file.path())[.size] as? Int ?? 0
        let head = "--\(boundary)\r\n"
            + "Content-Disposition: form-data; filename=\(Self.quoted(filename)); name=\(Self.quoted(field))\r\n"
            + "Content-Type: \(partContentType)\r\n"
            + "Content-Length: \(size)\r\n"
            + "\r\n"

        guard FileManager.default.createFile(atPath: destination.path(), contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path()])
        }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }

        try output.write(contentsOf: Data(head.utf8))
        var copying = true
        while copying {
            copying = try autoreleasepool {
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
                try output.write(contentsOf: chunk)
                return true
            }
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
