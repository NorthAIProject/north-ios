import XCTest

/// A workout from start to saved, against a local server with a seeded plan
/// and body weight (scripts/seed-training-uitest.sh → TEST_RUNNER_TRAINING_*).
final class WorkoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWorkoutIsTimedRestedAndSaved() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["TRAINING_EMAIL"], let password = env["TRAINING_PASSWORD"] else {
            throw XCTSkip("seed with scripts/seed-training-uitest.sh and pass TEST_RUNNER_TRAINING_EMAIL/PASSWORD")
        }
        let token = try Server.logIn(email: email, password: password)
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "Training")
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Monday'")).firstMatch)
        tap(app.buttons["Start Workout"])

        // The first set of the first exercise, with the server timing it.
        XCTAssertTrue(app.staticTexts["Goblet Squat"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Set 1 of 3 · 8-12 reps"].exists)
        let started = expectation(for: NSPredicate { _, _ in
            (try? Server.get("/api/v1/activity", token: token)["active"] as? [String: Any]) != nil
        }, evaluatedWith: nil)
        wait(for: [started], timeout: 20)
        attach(app, "01-set")

        // A set done: rest counts down, and can be skipped.
        tap(app.buttons["Done · Set 1"])
        XCTAssertTrue(app.staticTexts["REST"].waitForExistence(timeout: 5))
        attach(app, "02-rest")
        tap(app.buttons["Skip Rest"])
        XCTAssertTrue(app.buttons["Done · Set 2"].waitForExistence(timeout: 5))

        // Pause and resume go to the server too.
        tap(app.buttons["Pause"])
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        attach(app, "03-paused")
        tap(app.buttons["Resume"])

        // End early and save.
        tap(app.buttons["End"])
        tap(app.buttons["Finish and Save"])
        XCTAssertTrue(app.staticTexts["Workout done"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Saved to your activity. Your coach will see it."].waitForExistence(timeout: 15))
        attach(app, "04-summary")

        let overview = try Server.get("/api/v1/activity", token: token)
        XCTAssertNil(overview["active"], "the session is still open on the server")
        let recent = overview["recent"] as? [[String: Any]] ?? []
        XCTAssertEqual(recent.first?["status"] as? String, "completed")
        XCTAssertEqual(recent.first?["activityCode"] as? String, "strength_training")

        tap(app.buttons["Done"])
        XCTAssertTrue(app.buttons["Start Workout"].waitForExistence(timeout: 5))
    }
}
