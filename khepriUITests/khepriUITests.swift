import XCTest

/// Smoke test of the first run against a local server: sign up, answer the
/// wizard, take the tour, reach the tabs. Needs `north-web-app` running on
/// localhost:8090 (the Debug build's API base URL). Screenshots of each stage
/// are attached to the result bundle.
final class FirstRunUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstRunThroughWizardToTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()

        // A fresh account, created over the API: iOS's strong-password sheet
        // makes typing into a sign-up form unreliable under automation, and
        // sign-up itself is covered by the API tests. Sign in through the UI.
        let email = "ana+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        try createAccount(email: email, password: password)

        fill(app.textFields["Email address"], email)
        fill(app.secureTextFields["Password"], password)
        snapshot(app, "01-sign-in")
        app.buttons.matching(NSPredicate(format: "label == 'Sign In'")).element(boundBy: 1).tap()

        // Wizard. iOS offers to save the password first, as it would for anyone.
        XCTAssertTrue(app.buttons["Get Started"].waitForExistence(timeout: 15), "wizard did not open after sign-in")
        let savePassword = app.sheets["Save Password?"]
        if savePassword.waitForExistence(timeout: 5) {
            savePassword.buttons["Not Now"].tap()
        }
        snapshot(app, "02-welcome")
        tap(app.buttons["Get Started"])

        tap(app.buttons["Fitness"])
        tap(app.buttons["Learning"])
        snapshot(app, "03-focus")
        tap(app.buttons["Continue"])

        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Direct'")).firstMatch)
        snapshot(app, "04-style")
        tap(app.buttons["Continue"])

        fill(app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch, "Run a half marathon")
        snapshot(app, "05-goal")
        tap(app.buttons["Continue"])

        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 15), "answers were not accepted")
        snapshot(app, "06-health")
        tap(app.buttons["Not Now"])

        snapshot(app, "07-notifications")
        tap(app.buttons["Not Now"])

        // Tour, then the tabs.
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 15), "tour did not start")
        snapshot(app, "08-tour-today")
        tap(app.buttons["Next"])
        snapshot(app, "09-tour-coach")
        tap(app.buttons["Next"])
        snapshot(app, "10-tour-training")
        tap(app.buttons["Done"])

        tap(app.tabBars.buttons["Today"])
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
        snapshot(app, "11-today")

        tap(app.tabBars.buttons["More"])
        snapshot(app, "12-more")
    }

    private func createAccount(email: String, password: String) throws {
        var request = URLRequest(url: URL(string: "http://localhost:8090/api/v1/auth/signup")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "passwordConfirmation": password, "displayName": "Ana",
        ])
        let done = expectation(description: "signup")
        var status = 0
        URLSession.shared.dataTask(with: request) { _, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 15)
        XCTAssertEqual(status, 201, "is north-web-app running on localhost:8090?")
    }

    /// Waits out step transitions before tapping.
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)", file: file, line: line)
        let hittable = NSPredicate(format: "isHittable == true")
        let wait = XCTNSPredicateExpectation(predicate: hittable, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed, "not hittable: \(element)", file: file, line: line)
        element.tap()
    }

    private func fill(_ element: XCUIElement, _ text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "missing \(element)")
        element.tap()
        element.typeText(text)
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
