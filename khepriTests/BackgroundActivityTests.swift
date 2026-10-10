import Foundation
import Testing
import UIKit
@testable import khepri

/// Each long request asks iOS for time to finish if the app leaves the
/// foreground, and gives it back exactly once however the request ends.
@MainActor
struct BackgroundActivityTests {
    @Test func aFinishedRequestEndsItsGraceOnce() async {
        let tasks = FakeBackgroundTasks()

        let value = await BackgroundActivity.run("reply", tasks: tasks.tasks) { 42 }

        #expect(value == 42)
        #expect(tasks.begun == ["reply"])
        #expect(tasks.ended == [FakeBackgroundTasks.identifier])
    }

    @Test func aFailedRequestEndsItsGraceOnce() async {
        let tasks = FakeBackgroundTasks()

        await #expect(throws: URLError(.networkConnectionLost)) {
            try await BackgroundActivity.run("decide", tasks: tasks.tasks) { throw URLError(.networkConnectionLost) }
        }

        #expect(tasks.ended == [FakeBackgroundTasks.identifier])
    }

    @Test func aCancelledRequestEndsItsGraceOnce() async {
        let tasks = FakeBackgroundTasks()
        let work = Task {
            try await BackgroundActivity.run("upload", tasks: tasks.tasks) {
                try await Task.sleep(for: .seconds(10))
            }
        }
        for _ in 0..<100 where tasks.begun.isEmpty {
            await Task.yield()
        }
        work.cancel()

        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(tasks.ended == [FakeBackgroundTasks.identifier])
    }

    /// iOS ran out of patience before the request finished. The grace ends
    /// then, as iOS requires, and not a second time when the request does.
    @Test func expiryEndsTheGraceAndTheRequestDoesNotEndItAgain() async throws {
        let tasks = FakeBackgroundTasks()
        let (expired, expire) = AsyncStream.makeStream(of: Void.self)

        let work = Task {
            await BackgroundActivity.run("plan", tasks: tasks.tasks) {
                for await _ in expired { break }
                return "done"
            }
        }
        for _ in 0..<100 where tasks.expiration == nil {
            await Task.yield()
        }
        try #require(tasks.expiration != nil)
        tasks.expiration?()
        #expect(tasks.ended == [FakeBackgroundTasks.identifier])

        expire.yield()
        #expect(await work.value == "done")
        #expect(tasks.ended == [FakeBackgroundTasks.identifier], "ended exactly once")
    }

    /// Where iOS grants no time (an extension, or the budget is spent) there
    /// is nothing to end.
    @Test func noGraceGrantedMeansNothingToEnd() async {
        let tasks = FakeBackgroundTasks(grants: false)
        _ = await BackgroundActivity.run("reply", tasks: tasks.tasks) { 1 }
        #expect(tasks.ended.isEmpty)
    }
}

@MainActor
final class FakeBackgroundTasks {
    static let identifier = UIBackgroundTaskIdentifier(rawValue: 7)

    private(set) var begun: [String] = []
    private(set) var ended: [UIBackgroundTaskIdentifier] = []
    private(set) var expiration: (@MainActor () -> Void)?
    private let grants: Bool

    init(grants: Bool = true) {
        self.grants = grants
    }

    var tasks: BackgroundTasks {
        BackgroundTasks(
            begin: { name, expiration in
                self.begun.append(name)
                self.expiration = expiration
                return self.grants ? Self.identifier : .invalid
            },
            end: { self.ended.append($0) }
        )
    }
}
