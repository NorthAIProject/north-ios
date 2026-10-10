import Foundation
import NorthAPI
import Security
import Synchronization
import Testing
@testable import khepri

/// The clip goes up as a multipart body written to disk, since a background
/// URLSession uploads only from a file. It must match what the generated
/// client sent for `uploadFormCheck`.
struct MultipartFileBodyTests {
    @Test func writesOnePartAroundTheStreamedFile() throws {
        let directory = try temporaryDirectory()
        let clip = directory.appending(path: "clip.mov")
        let bytes = Data((0..<10).map { UInt8($0) })
        try bytes.write(to: clip)
        let destination = directory.appending(path: "body")

        // Smaller chunks than the file, so it is copied in several reads.
        try MultipartFileBody(boundary: "BOUNDARY").write(
            field: "video", file: clip, filename: "clip.mov", contentType: "text/plain",
            to: destination, chunkSize: 3
        )

        var expected = Data("""
        --BOUNDARY\r
        Content-Disposition: form-data; filename="clip.mov"; name="video"\r
        Content-Type: text/plain\r
        Content-Length: 10\r
        \r

        """.utf8)
        expected.append(bytes)
        expected.append(Data("\r\n--BOUNDARY--\r\n".utf8))
        #expect(try Data(contentsOf: destination) == expected)
    }

    @Test func theRequestCarriesTheBoundary() {
        #expect(MultipartFileBody(boundary: "B").contentType == "multipart/form-data; boundary=B")
        #expect(MultipartFileBody().boundary != MultipartFileBody().boundary)
    }

    @Test func quotesInAFilenameAreEscaped() throws {
        let directory = try temporaryDirectory()
        let clip = directory.appending(path: "clip.mov")
        try Data([1]).write(to: clip)
        let destination = directory.appending(path: "body")

        try MultipartFileBody(boundary: "B").write(
            field: "video", file: clip, filename: #"a"b.mov"#, contentType: "text/plain", to: destination
        )

        let text = try #require(String(bytes: try Data(contentsOf: destination), encoding: .utf8))
        #expect(text.contains(#"filename="a\"b.mov""#))
    }
}

@MainActor
struct FormCheckUploaderTests {
    @Test func startsABackgroundUploadWithTheSessionToken() async throws {
        let harness = try Harness()

        try await harness.uploader.upload(video: harness.clip)

        let started = try #require(harness.session.started.first)
        #expect(started.request.httpMethod == "POST")
        #expect(started.request.url?.absoluteString == "https://khepri.test/api/v1/form-checks")
        #expect(started.request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
        #expect(started.request.value(forHTTPHeaderField: "Accept") == "application/json")
        let upload = try #require(harness.uploader.uploads.first)
        let contentType = started.request.value(forHTTPHeaderField: "Content-Type")
        #expect(contentType == "multipart/form-data; boundary=\(upload.boundary)")
        #expect(started.uploadID == upload.id)
        #expect(FileManager.default.fileExists(atPath: started.file.path()))
        #expect(upload.isUploading)
    }

    /// The phone is locked and the token unreadable: say so, start nothing.
    @Test func aLockedKeychainStartsNothing() async throws {
        let harness = try Harness(token: { throw SecureStoreError.readFailed(errSecInteractionNotAllowed) })

        await #expect(throws: APIError.locked) {
            try await harness.uploader.upload(video: harness.clip)
        }
        #expect(harness.session.started.isEmpty)
        #expect(harness.uploader.uploads.isEmpty)
        #expect(try harness.bodyFiles().isEmpty)
    }

    @Test func acceptedRemovesTheUploadAndItsFile() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)

        await harness.uploader.didComplete(upload.id, status: 202, body: Data(), failure: nil)

        #expect(harness.uploader.uploads.isEmpty)
        #expect(harness.uploader.acceptedCount == 1)
        #expect(try harness.bodyFiles().isEmpty)
    }

    /// A refusal keeps the body so it can be sent again, until dismissed.
    @Test func aRefusalShowsTheServersMessageAndKeepsTheFileUntilDismissed() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)

        let body = Data(#"{"error":{"message":"Choose a video under 200 MB."}}"#.utf8)
        await harness.uploader.didComplete(upload.id, status: 422, body: body, failure: nil)

        #expect(harness.uploader.uploads.first?.failure == "Choose a video under 200 MB.")
        #expect(try harness.bodyFiles().count == 1)

        harness.uploader.dismiss(upload.id)

        #expect(harness.uploader.uploads.isEmpty)
        #expect(try harness.bodyFiles().isEmpty)
    }

    @Test func aDroppedConnectionIsAFailure() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)

        let dropped = APIError(URLError(.networkConnectionLost))
        await harness.uploader.didComplete(upload.id, status: nil, body: Data(), failure: dropped)

        #expect(harness.uploader.uploads.first?.failure == dropped.localizedDescription)
        #expect(harness.uploader.acceptedCount == 0)
    }

    @Test func aRejectedTokenEndsTheSession() async throws {
        let signedOut = Mutex(false)
        let harness = try Harness(onUnauthorized: { signedOut.withLock { $0 = true } })
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)

        await harness.uploader.didComplete(upload.id, status: 401, body: Data(), failure: nil)

        #expect(signedOut.withLock { $0 })
        #expect(harness.uploader.uploads.first?.failure != nil)
    }

    @Test func tryAgainSendsTheSameBodyAgain() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)
        await harness.uploader.didComplete(upload.id, status: 500, body: Data(), failure: nil)

        await harness.uploader.retry(upload.id)

        #expect(harness.session.started.count == 2)
        #expect(harness.session.started.last?.file == harness.session.started.first?.file)
        #expect(harness.uploader.uploads.first?.isUploading == true)
    }

    /// After a relaunch the list comes back from disk. An upload the system
    /// no longer has a task for is shown as stopped, yet a late answer for it
    /// still counts.
    @Test func aRelaunchReconcilesWithTheSessionsTasks() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)

        let relaunched = harness.relaunched()
        #expect(relaunched.uploads == harness.uploader.uploads)

        await relaunched.reconcile()
        #expect(relaunched.uploads.first?.failure != nil)

        await relaunched.didComplete(upload.id, status: 202, body: Data(), failure: nil)
        #expect(relaunched.uploads.isEmpty)
        #expect(try harness.bodyFiles().isEmpty)
    }

    @Test func aRelaunchKeepsUploadsTheSystemIsStillSending() async throws {
        let harness = try Harness()
        try await harness.uploader.upload(video: harness.clip)
        let upload = try #require(harness.uploader.uploads.first)
        harness.session.live.withLock { $0 = [upload.id] }

        let relaunched = harness.relaunched()
        await relaunched.reconcile()

        #expect(relaunched.uploads.first?.isUploading == true)
    }

    /// Everything one uploader test needs, in a directory of its own.
    @MainActor
    struct Harness {
        let session = FakeUploadSession()
        let directory: URL
        let defaults = UserDefaults.ephemeral()
        let clip: URL
        let token: @Sendable () async throws -> String?
        let onUnauthorized: @Sendable () async -> Void
        let uploader: FormCheckUploader

        init(
            token: @escaping @Sendable () async throws -> String? = { "session-token" },
            onUnauthorized: @escaping @Sendable () async -> Void = {}
        ) throws {
            let root = try temporaryDirectory()
            directory = root.appending(path: "uploads")
            clip = root.appending(path: "clip.mov")
            try Data(repeating: 7, count: 64).write(to: clip)
            self.token = token
            self.onUnauthorized = onUnauthorized
            uploader = FormCheckUploader(
                session: session, baseURL: URL(string: "https://khepri.test")!,
                token: token, onUnauthorized: onUnauthorized, directory: directory, defaults: defaults
            )
        }

        func relaunched() -> FormCheckUploader {
            FormCheckUploader(
                session: session, baseURL: URL(string: "https://khepri.test")!,
                token: token, onUnauthorized: onUnauthorized, directory: directory, defaults: defaults
            )
        }

        func bodyFiles() throws -> [URL] {
            guard FileManager.default.fileExists(atPath: directory.path()) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        }
    }
}

/// Records the uploads it is asked to start, and reports `live` as the
/// tasks the system still has.
final class FakeUploadSession: FormCheckUploadSession {
    struct Started: Sendable {
        let request: URLRequest
        let file: URL
        let uploadID: UUID
    }

    private let log = Mutex<[Started]>([])
    let live = Mutex<Set<UUID>>([])

    var started: [Started] { log.withLock { $0 } }

    func upload(_ request: URLRequest, fromFile file: URL, uploadID: UUID) {
        log.withLock { $0.append(Started(request: request, file: file, uploadID: uploadID)) }
    }

    func liveUploadIDs() async -> Set<UUID> {
        live.withLock { $0 }
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "khepri-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
