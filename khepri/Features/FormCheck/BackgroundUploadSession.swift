import Foundation
import NorthAPI
import Synchronization

/// The background URLSession form-check clips go up through.
///
/// iOS runs its tasks out of process: they carry on while the app is
/// suspended or killed, and the app is woken (or relaunched) to hear how
/// they ended. Creating the session again with the same identifier, as
/// `shared` does on first use, reconnects to those tasks.
nonisolated final class BackgroundUploadSession: NSObject, URLSessionDataDelegate, FormCheckUploadSession,
    @unchecked Sendable {
    static let identifier = "\(Bundle.main.bundleIdentifier ?? "com.fernandocorreia.khepri").form-check-uploads"
    static let shared = BackgroundUploadSession()

    /// Error bodies are a sentence or two; this bounds a misbehaving proxy.
    private static let maxResponseBytes = 64 * 1024

    /// Each running task's answer so far, by task identifier.
    private let responses = Mutex<[Int: Data]>([:])
    /// Set once in `init`; URLSession needs `self` as its delegate.
    private var session: URLSession!

    override private init() {
        super.init()
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func upload(_ request: URLRequest, fromFile file: URL, uploadID: UUID) {
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = uploadID.uuidString
        task.resume()
    }

    func liveUploadIDs() async -> Set<UUID> {
        let tasks = await session.allTasks
        return Set(tasks.compactMap { $0.taskDescription.flatMap(UUID.init(uuidString:)) })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responses.withLock { responses in
            let sofar = responses[dataTask.taskIdentifier, default: Data()]
            guard sofar.count < Self.maxResponseBytes else { return }
            responses[dataTask.taskIdentifier] = sofar + data.prefix(Self.maxResponseBytes - sofar.count)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let body = responses.withLock { $0.removeValue(forKey: task.taskIdentifier) } ?? Data()
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let failure = error.map { APIError($0) }
        Task { @MainActor in
            await FormCheckUploader.shared.didComplete(id, status: status, body: body, failure: failure)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            FormCheckUploader.shared.didFinishBackgroundEvents()
        }
    }
}
