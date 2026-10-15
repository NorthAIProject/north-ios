import XCTest

/// The appearance choice in Settings: drawn at once (Settings itself is a
/// sheet, so this also shows sheets follow it), kept across a relaunch, saved
/// to the account, and left alone by other profile saves.
final class AppearanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDarkIsDrawnAtOnceSurvivesARelaunchAndReachesTheAccount() throws {
        let email = "appearance+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"
        ])

        let app = launchSignedIn(email: email, password: password)
        openSettings(app)
        XCTAssertEqual(appearancePicker(app).label, "Appearance, System", "a new account should follow the phone")
        attachSettings(app, "01-settings-system")

        choose(app, "Dark")
        expectDrawn(app, dark: true)
        attachSettings(app, "02-settings-dark")
        waitForServer(token) { $0["appearance"] as? String == "dark" }

        // Kept on this iPhone: a relaunch draws dark before anything loads.
        app.terminate()
        app.launchArguments = app.launchArguments.filter { $0 != "-uitest-reset" }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "not signed in after relaunch")
        expectDrawn(app, dark: true)
        attach(app, "03-relaunched-dark")

        // Another profile save leaves the appearance alone.
        openSettings(app)
        tap(app.buttons["Coaching Style"])
        tap(app.buttons["Warm"])
        tap(app.buttons["Save"])
        waitForServer(token) { $0["coachingTone"] as? String == "warm" && $0["appearance"] as? String == "dark" }
        app.navigationBars.buttons.element(boundBy: 0).tap()

        choose(app, "Light")
        expectDrawn(app, dark: false)
        attachSettings(app, "04-settings-light")
        waitForServer(token) { $0["appearance"] as? String == "light" }

        choose(app, "System")
        XCTAssertEqual(appearancePicker(app).label, "Appearance, System")
        attachSettings(app, "05-settings-system-again")
        waitForServer(token) { $0["appearance"] as? String == "system" }
    }

    // MARK: - Steps

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        openTab(app, "More")
        // The last row of a lazy list: not in the tree until scrolled to.
        let settings = app.buttons["Settings"]
        for _ in 0..<4 where !settings.isHittable { app.swipeUp() }
        tap(settings)
    }

    /// The App section, where the picker is, in view.
    @MainActor
    private func attachSettings(_ app: XCUIApplication, _ name: String) {
        app.swipeUp()
        attach(app, name)
    }

    @MainActor
    private func appearancePicker(_ app: XCUIApplication) -> XCUIElement {
        // A menu picker reads as one button: "Appearance, Dark".
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        return picker
    }

    @MainActor
    private func choose(_ app: XCUIApplication, _ option: String) {
        tap(appearancePicker(app))
        attach(app, "menu-\(option.lowercased())")
        tap(app.buttons[option].firstMatch)
        let chosen = expectation(for: NSPredicate(format: "label == %@", "Appearance, \(option)"),
                                 evaluatedWith: appearancePicker(app))
        wait(for: [chosen], timeout: 10)
    }

    /// Dark and light differ most in the background, so the screen's mean
    /// brightness tells them apart without depending on any one control.
    @MainActor
    private func expectDrawn(_ app: XCUIApplication, dark: Bool, file: StaticString = #filePath, line: UInt = #line) {
        var brightness = 0.0
        let deadline = Date.now.addingTimeInterval(5)
        repeat {
            brightness = meanBrightness(XCUIScreen.main.screenshot().image)
            if dark ? brightness < 0.3 : brightness > 0.6 { return }
            usleep(250_000)
        } while Date.now < deadline
        attach(app, dark ? "not-dark" : "not-light")
        XCTFail("expected \(dark ? "dark" : "light"), mean brightness \(brightness)", file: file, line: line)
    }

    private func meanBrightness(_ image: UIImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cgImage = image.cgImage else { return }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let (red, green, blue) = (Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2]))
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return total / Double(side * side) / 255
    }

    private func waitForServer(_ token: String, until condition: @escaping ([String: Any]) -> Bool) {
        let saved = expectation(for: NSPredicate { _, _ in
            condition((try? Server.get("/api/v1/settings/profile", token: token)) ?? [:])
        }, evaluatedWith: nil)
        wait(for: [saved], timeout: 15)
    }
}
