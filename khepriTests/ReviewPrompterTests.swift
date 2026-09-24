import Foundation
import Testing
@testable import khepri

@MainActor
struct ReviewPrompterTests {
    /// A clock the test moves by hand.
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        func advance(days: Double) { now += days * 24 * 60 * 60 }
    }

    private func makePrompter(_ clock: Clock, defaults: UserDefaults = .ephemeral()) -> ReviewPrompter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return ReviewPrompter(defaults: defaults, calendar: calendar, now: { clock.now })
    }

    /// Records one success per day for `days` days, starting tomorrow.
    private func succeed(on days: Int, _ prompter: ReviewPrompter, _ clock: Clock) {
        for _ in 0..<days {
            clock.advance(days: 1)
            prompter.recordSuccess()
        }
    }

    @Test func promptsAfterTheThirdDayWithAReply() {
        let clock = Clock()
        let prompter = makePrompter(clock)

        succeed(on: 2, prompter, clock)
        #expect(!prompter.isPromptDue)

        succeed(on: 1, prompter, clock)
        #expect(prompter.successCount == 3)
        #expect(prompter.isPromptDue)
    }

    @Test func countsAtMostOnceADay() {
        let clock = Clock()
        let prompter = makePrompter(clock)
        clock.advance(days: 1)

        for _ in 0..<5 {
            prompter.recordSuccess()
            clock.now += 60
        }
        #expect(prompter.successCount == 1)
        #expect(!prompter.isPromptDue)
    }

    @Test func neverPromptsInTheFirstDay() {
        let clock = Clock()
        let defaults = UserDefaults.ephemeral()
        // Three earlier days already counted, but this install is new.
        defaults.set(3, forKey: "review.successCount")
        let prompter = makePrompter(clock, defaults: defaults)

        clock.now += 23 * 60 * 60
        prompter.recordSuccess()
        #expect(!prompter.shouldPrompt)

        clock.now += 2 * 60 * 60
        #expect(prompter.shouldPrompt)
    }

    @Test func waitsOneHundredTwentyDaysBetweenPrompts() {
        let clock = Clock()
        let prompter = makePrompter(clock)
        succeed(on: 3, prompter, clock)
        prompter.didPrompt()

        succeed(on: 3, prompter, clock)
        #expect(!prompter.isPromptDue)

        clock.advance(days: 110)
        prompter.recordSuccess()
        #expect(!prompter.isPromptDue)   // 113 days since the prompt

        clock.advance(days: 10)                   // 123
        prompter.recordSuccess()
        #expect(prompter.isPromptDue)
    }

    @Test func turnedOffNeverPrompts() {
        let clock = Clock()
        let defaults = UserDefaults.ephemeral()
        let prompter = makePrompter(clock, defaults: defaults)
        prompter.isEnabled = false

        succeed(on: 5, prompter, clock)
        #expect(!prompter.isPromptDue)
        #expect(!makePrompter(clock, defaults: defaults).isEnabled)
    }

    @Test func enabledByDefault() {
        #expect(makePrompter(Clock()).isEnabled)
    }

    @Test func promptingResetsTheCountAndRecordsTheTime() {
        let clock = Clock()
        let defaults = UserDefaults.ephemeral()
        let prompter = makePrompter(clock, defaults: defaults)
        succeed(on: 3, prompter, clock)

        prompter.didPrompt()
        #expect(prompter.successCount == 0)
        #expect(!prompter.isPromptDue)
        #expect(defaults.object(forKey: "review.lastPromptAt") as? Date == clock.now)
    }

    @Test func skippingWaitsForTheNextSuccess() {
        let clock = Clock()
        let prompter = makePrompter(clock)
        succeed(on: 3, prompter, clock)

        prompter.skipPrompt()
        #expect(!prompter.isPromptDue)
        #expect(prompter.successCount == 3)

        clock.now += 60
        prompter.recordSuccess()
        #expect(prompter.isPromptDue)
    }
}
