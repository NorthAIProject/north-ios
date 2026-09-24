import XCTest

/// Training against a local server with a seeded plan
/// (scripts/seed-training-uitest.sh → TEST_RUNNER_TRAINING_*).
final class TrainingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStartTimeSwapAndLibrary() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)

        let app = launchSignedIn(email: email, password: password)

        openTab(app, "Training")
        XCTAssertTrue(app.staticTexts["Strength base"].waitForExistence(timeout: 15))
        attach(app, "01-plan")

        // Thursday has no start time; give it one and check the server has it.
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Thursday'")).firstMatch)
        // A switch row's centre is its label; flip the switch itself.
        let toggle = app.switches["Set a start time"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let saved = expectation(for: NSPredicate { _, _ in
            let plans = (try? Server.get("/api/v1/training/plans", token: token)["plans"] as? [[String: Any]]) ?? []
            let days = plans.first?["days"] as? [[String: Any]] ?? []
            return days.count == 2 && days[1]["startTime"] as? String != nil
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 20)
        attach(app, "02-day")

        // Swap the first exercise for a suggestion.
        let first = app.cells.containing(NSPredicate(format: "label CONTAINS 'Push-up'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.swipeLeft()
        tap(app.buttons["Swap"])
        XCTAssertTrue(app.navigationBars["Swap Exercise"].waitForExistence(timeout: 10))
        attach(app, "03-swap")
        let suggestion = app.collectionViews.buttons.element(boundBy: 0)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 15), "no suggestions")
        tap(suggestion)
        XCTAssertFalse(app.navigationBars["Swap Exercise"].waitForExistence(timeout: 2))

        // The library.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["Training Options"])
        tap(app.buttons["Exercise Library"])
        let search = app.searchFields.firstMatch
        type(search, "push")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'push'")).firstMatch.waitForExistence(timeout: 15), "no search results")
        attach(app, "04-library")
    }




}
