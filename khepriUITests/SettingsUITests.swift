import XCTest

/// Settings against a local server: a change made here is checked on the
/// server, not just on screen.
final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoachingStyleSavesToTheServerAndAccountDeletionSignsOut() throws {
        let email = "settings+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])

        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Settings"])
        attach(app, "01-settings")

        // Coaching style and tone, saved and read back from the server.
        tap(app.buttons["Coaching Style"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Socratic'")).firstMatch)
        tap(app.buttons["Warm"])
        attach(app, "02-coaching")
        tap(app.buttons["Save"])
        let saved = expectation(for: NSPredicate { _, _ in
            let profile = (try? Server.get("/api/v1/settings/profile", token: token)) ?? [:]
            return profile["coachingTone"] as? String == "warm"
                && (profile["coachingStyle"] as? String)?.hasPrefix("Ask questions") == true
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 15)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // An agent connection shows its token once.
        tap(app.buttons["Agents"])
        tap(app.buttons["Connect an Agent"])
        type(app.textFields["Name, e.g. Work laptop"], "Laptop")
        tap(app.buttons["Create"])
        XCTAssertTrue(app.buttons["Copy Token"].waitForExistence(timeout: 15), "no token sheet")
        attach(app, "03-token")
        tap(app.buttons["Copy Token"])
        tap(app.buttons["Done"])
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Deletion needs the email typed back, then it signs out.
        // Form rows below the fold are not in the tree until scrolled to.
        let delete = app.buttons["Delete Account"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        tap(delete)
        type(app.textFields[email], email)
        attach(app, "04-delete")
        tap(app.buttons["Delete"])
        XCTAssertTrue(app.textFields["Email address"].waitForExistence(timeout: 20), "not signed out after deletion")
    }




}
