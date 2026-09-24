import XCTest

/// What every flow test needs: signing in, getting past the system's password
/// prompts, finding the real tab, and tapping only once something is ready.
extension XCTestCase {
    /// Launches from a clean install (no session, no saved progress, tour
    /// done) and signs in through the UI.
    @MainActor
    func launchSignedIn(email: String, password: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-reset", "-uitest-skip-tour"]
        app.launch()
        type(app.textFields["Email address"], email, file: file, line: line)
        type(app.secureTextFields["Password"], password, file: file, line: line)
        app.buttons.matching(NSPredicate(format: "label == 'Sign In'")).element(boundBy: 1).tap()
        dismissSavePassword(app)
        return app
    }

    /// iOS offers to save the password after sign-in, as it would for anyone,
    /// sometimes seconds later. On iOS 26 the prompt is system UI outside the
    /// app's own tree, so both the app and SpringBoard are searched. Answer it
    /// the way a person would.
    @MainActor
    func dismissSavePassword(_ app: XCUIApplication, within seconds: TimeInterval = 10) {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if answerSavePassword(app) { return }
            usleep(250_000)
        }
    }

    /// Answers the save-password prompt if it is showing. The waiting helpers
    /// call this on every poll, because the prompt can arrive at any moment
    /// after sign-in.
    @MainActor
    @discardableResult
    func answerSavePassword(_ app: XCUIApplication) -> Bool {
        for owner in [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")] {
            let notNow = owner.buttons["Not Now"]
            if owner.staticTexts["Save Password?"].exists, notNow.exists, notNow.isHittable {
                notNow.tap()
                return true
            }
        }
        return false
    }

    /// The iOS 26 tab bar exposes each tab more than once to accessibility,
    /// and the first match can be an off-screen copy. Tap the one on screen.
    @MainActor
    func openTab(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date.now.addingTimeInterval(15)
        while Date.now < deadline {
            answerSavePassword(app)
            let candidates = app.tabBars.buttons.allElementsBoundByIndex.filter { $0.label == name && $0.isHittable }
            // A tap on a copy, or during a transition, can leave the tab
            // unchanged; only a selected tab counts.
            if candidates.contains(where: \.isSelected) { return }
            candidates.first?.tap()
            usleep(500_000)
        }
        attach(app, "no-\(name)-tab")
        XCTFail("no tappable \(name) tab", file: file, line: line)
    }

    @MainActor
    func type(_ element: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)", file: file, line: line)
        element.tap()
        element.typeText(text)
    }

    /// Waits out transitions: exists, then hittable, then tap.
    @MainActor
    func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline {
            answerSavePassword(app)
            if element.exists, element.isHittable {
                element.tap()
                return
            }
            usleep(250_000)
        }
        XCTFail(element.exists ? "never became tappable: \(element)" : "missing \(element)", file: file, line: line)
    }

    @MainActor
    func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
