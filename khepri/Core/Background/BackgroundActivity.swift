import UIKit

/// Keeps a request alive for a while after the app leaves the foreground.
///
/// iOS suspends an app seconds after it is backgrounded or the phone locks,
/// and a request in flight then dies with "the network connection was lost".
/// A coach reply, an approved plan or an upload often takes longer than the
/// moment the person spends looking away, so each one asks for background
/// time (`beginBackgroundTask`) while it runs and gives it back when it ends.
///
/// App target only: extensions cannot reach `UIApplication.shared`.
enum BackgroundActivity {
    /// Runs `work` with background time requested under `name`, ending that
    /// request exactly once whether `work` returns, throws or is cancelled,
    /// or iOS runs out of time first.
    static func run<T, Failure: Error>(
        _ name: String,
        tasks: BackgroundTasks = .application,
        isolation: isolated (any Actor)? = #isolation,
        _ work: () async throws(Failure) -> T
    ) async throws(Failure) -> T {
        let grace = await BackgroundGrace(name: name, tasks: tasks)
        let result: Result<T, Failure>
        do {
            result = .success(try await work())
        } catch {
            result = .failure(error)
        }
        await grace.end()
        return try result.get()
    }
}

/// The two UIApplication calls the grace makes, so tests can watch them.
struct BackgroundTasks: Sendable {
    typealias Expiration = @MainActor () -> Void

    var begin: @MainActor @Sendable (_ name: String, _ expiration: @escaping Expiration) -> UIBackgroundTaskIdentifier
    var end: @MainActor @Sendable (UIBackgroundTaskIdentifier) -> Void

    static let application = BackgroundTasks(
        begin: { name, expiration in
            UIApplication.shared.beginBackgroundTask(withName: name, expirationHandler: expiration)
        },
        end: { UIApplication.shared.endBackgroundTask($0) }
    )
}

/// One stretch of background time, ended once: by the work finishing or by
/// iOS's expiration handler, whichever comes first.
@MainActor
private final class BackgroundGrace {
    private let tasks: BackgroundTasks
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String, tasks: BackgroundTasks) {
        self.tasks = tasks
        identifier = tasks.begin(name) { [weak self] in self?.end() }
    }

    func end() {
        guard identifier != .invalid else { return }
        tasks.end(identifier)
        identifier = .invalid
    }
}
