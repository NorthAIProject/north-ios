import Foundation
import os

/// Where the workout in progress is kept between launches. A protocol so the
/// session's tests can keep it in memory.
protocol WorkoutSnapshotStoring: Sendable {
    /// The snapshot to resume, or nil when there is none, or it is unreadable
    /// or too old; either of those is deleted.
    func load(now: Date) -> WorkoutSnapshot?
    func save(_ snapshot: WorkoutSnapshot)
    func clear()
}

extension WorkoutSnapshotStoring {
    func load() -> WorkoutSnapshot? { load(now: .now) }
}

/// One JSON file in Application Support. Only the app reads it, so it does
/// not need the App Group; it is small enough to write on every change.
struct WorkoutSnapshotStore: WorkoutSnapshotStoring {
    /// A workout not touched for this long was abandoned, not paused.
    static let maxAge: TimeInterval = 12 * 60 * 60

    let url: URL

    init(url: URL = Self.defaultURL) {
        self.url = url
    }

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(components: "Workout", "in-progress.json")
    }

    private var log: Logger { Logger(subsystem: "com.fernandocorreia.khepri", category: "workout-snapshot") }

    func load(now: Date) -> WorkoutSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            let snapshot = try JSONDecoder().decode(WorkoutSnapshot.self, from: data)
            guard snapshot.version == WorkoutSnapshot.currentVersion,
                  now.timeIntervalSince(snapshot.savedAt) <= Self.maxAge else {
                clear()
                return nil
            }
            return snapshot
        } catch {
            log.error("workout snapshot unreadable, discarded: \(error.localizedDescription, privacy: .public)")
            clear()
            return nil
        }
    }

    func save(_ snapshot: WorkoutSnapshot) {
        do {
            let folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Dates as the encoder's default, a full-precision number: ISO 8601
            // would round rest ends and set times to whole seconds.
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("workout snapshot not saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear() {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            log.error("workout snapshot not removed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
