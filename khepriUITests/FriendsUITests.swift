import XCTest

/// Friends against a local server: the seeded account was invited by Leo, so
/// they follow each other, and Leo shares an achieved goal; Zoe's invite link, opened from outside the app,
/// connects Zoe too.
///
/// Pass TEST_RUNNER_FRIENDS_EMAIL, TEST_RUNNER_FRIENDS_PASSWORD and
/// TEST_RUNNER_FRIENDS_INVITE (a code of somebody the account has no
/// connection with yet).
final class FriendsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFriendsShowsConnectionsAndAnInviteLinkConnects() throws {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["FRIENDS_EMAIL"], let password = env["FRIENDS_PASSWORD"], let code = env["FRIENDS_INVITE"] else {
            throw XCTSkip("seed accounts and pass TEST_RUNNER_FRIENDS_EMAIL/PASSWORD/INVITE")
        }
        let app = launchSignedIn(email: email, password: password)

        openTab(app, "More")
        tap(app.buttons["Friends"])
        XCTAssertTrue(app.navigationBars["Friends"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Share Your Invite Link"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Leo"].waitForExistence(timeout: 10), "the inviter is not listed")
        // Leo shares goals and achieved one: it is in Recent, with kudos.
        XCTAssertTrue(app.staticTexts["Achieved a goal: Run a half marathon"].waitForExistence(timeout: 10), "Leo's goal is not in Recent")
        tap(app.buttons["Give kudos"])
        XCTAssertTrue(app.buttons["Take back kudos"].waitForExistence(timeout: 10), "kudos did not stick")
        attach(app, "01-friends")

        // A handle nobody has: the server's own words, not a crash.
        let field = app.textFields["@their_handle"]
        for _ in 0..<6 where !field.isHittable { app.swipeUp() }
        type(field, "nobody_has_this_1")
        tap(app.buttons["Ask to Follow"])
        XCTAssertTrue(app.staticTexts["Nobody has that handle."].waitForExistence(timeout: 10))

        // Zoe's link from outside the app: Friends opens with Zoe in it.
        XCUIDevice.shared.system.open(URL(string: "khepri://i/\(code)")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["Open"].waitForExistence(timeout: 3) { springboard.buttons["Open"].tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.staticTexts["Zoe"].waitForExistence(timeout: 15), "the invite did not connect Zoe")
        attach(app, "02-invited")
    }
}
