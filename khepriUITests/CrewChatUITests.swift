import XCTest

/// Crew chat against a local server (Debug's base URL, localhost:8090), as
/// the joiner of a crew whose owner has posted three messages. The joiner has
/// not accepted the crew rules yet, so the first post asks for them.
///
/// Seed with scripts/seed-crews-uitest.sh and pass TEST_RUNNER_CREW_CHAT_EMAIL
/// and TEST_RUNNER_CREW_CHAT_PASSWORD. The run accepts the rules, reports and
/// blocks, so seed again before every run.
final class CrewChatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The rules come before the first post, any message can be reported,
    /// and blocking its author from the message menu hides all they wrote
    /// (App Store guideline 1.2).
    @MainActor
    func testChatRulesReportBlock() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["CREW_CHAT_EMAIL"], let password = env["CREW_CHAT_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-crews-uitest.sh and pass TEST_RUNNER_CREW_CHAT_EMAIL/PASSWORD")
        }
        let app = launchSignedIn(email: email, password: password)
        openTab(app, "More")
        tap(labelled(app.buttons, "Crews"))
        tap(labelled(app.buttons, "Iron rats"))

        let welcome = app.staticTexts["Welcome to Iron rats!"]
        let legDay = app.staticTexts["Leg day tomorrow at 7."]
        let fiveK = app.staticTexts["Who is in for the 5k on Sunday?"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 20), "the seeded messages did not load")
        XCTAssertTrue(legDay.exists)
        XCTAssertTrue(fiveK.exists)
        attach(app, "01-chat")

        // The first post asks for the rules; agreeing sends it.
        type(app.textFields["composer"], "hi")
        tap(app.buttons["Send"])
        let agree = app.buttons["crew-rules-agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), "no rules before the first post")
        attach(app, "02-rules")
        tap(agree)
        let mine = app.staticTexts["hi"]
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "the message did not post after agreeing")
        XCTAssertTrue(waitUntilGone(app.buttons["crew-rules-agree"]))

        // Reporting a message takes it off the screen.
        welcome.press(forDuration: 1.2)
        tap(app.buttons["Report"])
        tap(app.buttons["Spam"])
        attach(app, "03-report")
        tap(app.buttons["Send report"])
        XCTAssertTrue(waitUntilGone(welcome), "the reported message is still showing")

        // Blocking the author from the menu hides everything they wrote.
        legDay.press(forDuration: 1.2)
        tap(app.buttons["Block Owner"])
        tap(confirmBlock(app))
        XCTAssertTrue(waitUntilGone(legDay), "the blocked author's message is still showing")
        XCTAssertTrue(waitUntilGone(fiveK), "the blocked author's other message is still showing")
        XCTAssertFalse(app.staticTexts["Owner"].exists, "a message by the blocked author is still showing")
        XCTAssertTrue(mine.exists, "the joiner's own message went with the block")
        attach(app, "04-blocked")
    }

    /// The confirmation's "Block", not the menu's "Block Owner": iOS draws the
    /// dialog as a sheet or a popover, so take the one on screen.
    @MainActor
    private func confirmBlock(_ app: XCUIApplication) -> XCUIElement {
        let buttons = app.buttons.matching(NSPredicate(format: "label == 'Block'"))
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if let button = buttons.allElementsBoundByIndex.first(where: \.isHittable) { return button }
            usleep(250_000)
        }
        return buttons.firstMatch
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Rows read their title and details as one label, so match on part of it.
    private func labelled(_ query: XCUIElementQuery, _ text: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
}
