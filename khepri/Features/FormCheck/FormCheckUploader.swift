import Foundation
import NorthAPI
import Observation

/// A form-check clip on its way to the server.
///
/// Kept on disk with its multipart body, so it outlives the app being
/// suspended, killed, or relaunched by iOS to hear how the upload ended.
nonisolated struct FormCheckUpload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The multipart body's file name, inside the uploader's directory.
    let bodyFile: String
    let boundary: String
    /// Why the last attempt failed; nil while it is being sent.
    var failure: String?

    var isUploading: Bool { failure == nil }
}

/// What the uploader needs from URLSession. The app passes the background
/// session; tests pass a fake.
nonisolated protocol FormCheckUploadSession: Sendable {
    /// Starts sending `file`, the task tagged with `uploadID`.
    func upload(_ request: URLRequest, fromFile file: URL, uploadID: UUID)
    /// The uploads the system still has a task for.
    func liveUploadIDs() async -> Set<UUID>
}

/// Sends form-check clips through a background URLSession, so an upload
/// carries on after the app leaves the screen, is suspended or is killed.
///
/// Owns the list of uploads in flight or failed. The server answers 202 and
/// analyses the clip later; the screen reloads its checks when
/// `acceptedCount` moves. A body file is deleted only once the server has
/// accepted it, or when a failed upload is dismissed.
@MainActor
@Observable
final class FormCheckUploader {
    static let shared = FormCheckUploader(
        session: BackgroundUploadSession.shared,
        baseURL: AppEnvironment.apiBaseURL,
        token: { try await AuthSessionManager.shared.validAccessToken() },
        onUnauthorized: { await AuthSessionManager.shared.invalidateSession() },
        directory: .applicationSupportDirectory.appending(path: "FormCheckUploads"),
        defaults: .standard
    )

    private(set) var uploads: [FormCheckUpload]
    /// Moves each time the server accepts a clip.
    private(set) var acceptedCount = 0
    /// Handed over by the app delegate when iOS wakes the app for this
    /// session's events; called once they have all been delivered.
    @ObservationIgnored var backgroundEventsCompletion: (() -> Void)?

    @ObservationIgnored private let session: any FormCheckUploadSession
    @ObservationIgnored private let baseURL: URL
    @ObservationIgnored private let token: @Sendable () async throws -> String?
    @ObservationIgnored private let onUnauthorized: @Sendable () async -> Void
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "formCheck.uploads"
    static let interrupted = "The upload stopped before it finished."
    static let missingBody = "The clip is no longer on this iPhone. Choose it again."

    init(
        session: any FormCheckUploadSession,
        baseURL: URL,
        token: @escaping @Sendable () async throws -> String?,
        onUnauthorized: @escaping @Sendable () async -> Void,
        directory: URL,
        defaults: UserDefaults
    ) {
        self.session = session
        self.baseURL = baseURL
        self.token = token
        self.onUnauthorized = onUnauthorized
        self.directory = directory
        self.defaults = defaults
        uploads = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([FormCheckUpload].self, from: $0) } ?? []
    }

    /// Writes `video` into a multipart body and starts sending it. Returns
    /// once the upload has started; the caller may delete `video` then.
    /// Throws `APIError.locked`, and starts nothing, when the session token
    /// cannot be read.
    func upload(video: URL) async throws {
        let token = try await sessionToken()
        let body = MultipartFileBody()
        let upload = FormCheckUpload(id: UUID(), bodyFile: "\(UUID().uuidString).multipart", boundary: body.boundary)
        let bodyURL = try bodyDirectory().appending(path: upload.bodyFile)
        do {
            try await Self.write(body, video: video, to: bodyURL)
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
        // Listed before it starts, so even an instant answer finds it.
        uploads.insert(upload, at: 0)
        save()
        send(upload, token: token)
    }

    /// Sends a failed upload's body again.
    func retry(_ id: UUID) async {
        do {
            let token = try await sessionToken()
            guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
            guard FileManager.default.fileExists(atPath: bodyURL(uploads[index]).path()) else {
                uploads[index].failure = Self.missingBody
                save()
                return
            }
            uploads[index].failure = nil
            save()
            send(uploads[index], token: token)
        } catch {
            guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
            uploads[index].failure = error.localizedDescription
            save()
        }
    }

    /// Forgets a failed upload and deletes its body.
    func dismiss(_ id: UUID) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        remove(at: index)
    }

    /// How a task ended: `status` and `body` are the server's answer, or
    /// `failure` says why there was none.
    func didComplete(_ id: UUID, status: Int?, body: Data, failure: APIError?) async {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        if failure == nil, status == 202 {
            remove(at: index)
            acceptedCount += 1
            return
        }
        let error = failure ?? status.map { APIError(status: $0, body: body) } ?? .invalidResponse
        uploads[index].failure = error.localizedDescription
        save()
        if error.isUnauthorized {
            await onUnauthorized()
        }
    }

    /// At launch: an upload the system no longer has a task for will not
    /// finish. Its answer may still be on its way, and still counts if it
    /// comes.
    func reconcile() async {
        let live = await session.liveUploadIDs()
        for index in uploads.indices where uploads[index].isUploading && !live.contains(uploads[index].id) {
            uploads[index].failure = Self.interrupted
        }
        save()
    }

    /// Every event iOS woke the app for has been delivered.
    func didFinishBackgroundEvents() {
        let completion = backgroundEventsCompletion
        backgroundEventsCompletion = nil
        completion?()
    }

    private func send(_ upload: FormCheckUpload, token: String) {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/form-checks"))
        request.httpMethod = "POST"
        request.setValue(MultipartFileBody(boundary: upload.boundary).contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        session.upload(request, fromFile: bodyURL(upload), uploadID: upload.id)
    }

    private func sessionToken() async throws(APIError) -> String {
        let current: String?
        do {
            current = try await token()
        } catch {
            throw .locked
        }
        guard let current, !current.isEmpty else { throw .unauthorized(nil) }
        return current
    }

    private func remove(at index: Int) {
        try? FileManager.default.removeItem(at: bodyURL(uploads[index]))
        uploads.remove(at: index)
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(uploads), forKey: Self.storageKey)
    }

    private func bodyURL(_ upload: FormCheckUpload) -> URL {
        directory.appending(path: upload.bodyFile)
    }

    /// Not backed up: a body is only kept until the server has it.
    private func bodyDirectory() throws -> URL {
        var url = directory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    /// Off the main actor: copying 200 MB takes a moment.
    @concurrent
    private nonisolated static func write(_ body: MultipartFileBody, video: URL, to destination: URL) async throws {
        try body.write(
            field: "video",
            file: video,
            filename: video.lastPathComponent,
            // What the generated client labels every binary part.
            contentType: "text/plain",
            to: destination
        )
    }
}
