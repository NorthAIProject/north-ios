import Foundation
import NorthAPI
import OpenAPIRuntime

typealias FormCheck = Components.Schemas.FormCheck

protocol FormCheckServicing: Sendable {
    func checks() async throws -> [FormCheck]
    func check(_ id: String) async throws -> FormCheck
    func upload(video: URL) async throws -> FormCheck
}

struct FormCheckService: FormCheckServicing {
    var api: Client = API.shared

    func checks() async throws -> [FormCheck] {
        try await NorthAPI.call { try await api.listFormChecks().ok.body.json.checks }
    }

    func check(_ id: String) async throws -> FormCheck {
        try await NorthAPI.call { try await api.getFormCheck(path: .init(analysisID: id)).ok.body.json }
    }

    /// Streams the file rather than loading it: a clip can be 200 MB.
    func upload(video: URL) async throws -> FormCheck {
        let size = (try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let handle = try FileHandle(forReadingFrom: video)
        defer { try? handle.close() }
        let chunks = AsyncThrowingStream<ArraySlice<UInt8>, Error> { continuation in
            while let data = try? handle.read(upToCount: 1 << 20), !data.isEmpty {
                continuation.yield(ArraySlice(data))
            }
            continuation.finish()
        }
        let body = HTTPBody(chunks, length: size.map { .known($0) } ?? .unknown, iterationBehavior: .single)
        let part = OpenAPIRuntime.MultipartPart(
            payload: Operations.UploadFormCheck.Input.Body.MultipartFormPayload.VideoPayload(body: body),
            filename: video.lastPathComponent
        )
        return try await NorthAPI.call {
            try await api.uploadFormCheck(body: .multipartForm([.video(part)])).accepted.body.json
        }
    }
}
