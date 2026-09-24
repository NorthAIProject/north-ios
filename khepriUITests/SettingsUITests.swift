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

        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-skip-tour"]
        app.launch()
        type(app.textFields["Email address"], email)
        type(app.secureTextFields["Password"], password)
        app.buttons.matching(NSPredicate(format: "label == 'Sign In'")).element(boundBy: 1).tap()
        let savePassword = app.sheets["Save Password?"]
        if savePassword.waitForExistence(timeout: 5) { savePassword.buttons["Not Now"].tap() }

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

    // MARK: - Helpers

    private func openTab(_ app: XCUIApplication, _ name: String) {
        let deadline = Date.now.addingTimeInterval(15)
        while Date.now < deadline {
            if let tab = app.tabBars.buttons.allElementsBoundByIndex.first(where: { $0.label == name && $0.isHittable }) {
                tab.tap()
                return
            }
            usleep(250_000)
        }
        XCTFail("no tappable \(name) tab")
    }

    private func type(_ element: XCUIElement, _ text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)")
        element.tap()
        element.typeText(text)
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)")
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 15), .completed, "never became tappable: \(element)")
        element.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
