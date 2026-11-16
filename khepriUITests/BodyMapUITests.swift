import XCTest

/// The body figure on Today against a local server: a logged squat heats the
/// figure, and a tap on the thigh names the muscle and leads to its exercises.
final class BodyMapUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSquatHeatsTheFigureAndATapOpensItsExercises() throws {
        let email = "bodymap+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        let yesterday = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-24 * 3600))
        // Under 100 kg: a heavier set earns the Century award, whose sheet
        // would cover Today.
        for set in 1...4 {
            try Server.post("/api/v1/lifts/sets", token: token, body: [
                "exerciseName": "Box squat", "exerciseSlug": "barbell-back-squat-to-box",
                "setNumber": set, "weightKg": 60, "reps": 5, "performedAt": yesterday,
            ])
        }
        let map = try Server.get("/api/v1/body/map", token: token)
        let quads = (map["muscles"] as? [[String: Any]])?.first { $0["id"] as? String == "quads" }
        XCTAssertGreaterThan(quads?["intensity"] as? Double ?? 0, 0.5, "the squat did not heat the quads")

        let app = launchSignedIn(email: email, password: password)
        // The body card sits below the day's cards; scroll down to it.
        let figure = app.descendants(matching: .any).matching(identifier: "body-map").firstMatch
        dismissSavePassword(app)
        for _ in 0..<12 where !(figure.exists && figure.isHittable) {
            answerSavePassword(app)
            app.swipeUp()
            usleep(400_000)
        }
        attach(app, "00-today")
        XCTAssertTrue(figure.exists, "no body figure on Today")
        XCTAssertTrue((figure.value as? String ?? "").contains("Quads"), "figure value: \(figure.value ?? "nil")")
        sleep(2)
        attach(app, "01-today-figure")

        // The front thigh: the figure faces the camera, a leg either side of centre.
        let open = app.buttons["body-open-training"]
        for dx in [0.45, 0.5, 0.4, 0.55] where !open.exists {
            figure.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.62)).tap()
            _ = open.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(open.exists, "a tap on the thigh opened nothing")
        XCTAssertTrue(app.staticTexts["Quads"].exists, "the callout does not name the quads")
        attach(app, "02-callout")

        tap(open)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10), "Open in Training did not open the library")
        attach(app, "03-library")
    }

    /// Soreness mode: a sore thigh turns the figure's quads red, and a tap on
    /// the thigh opens the body sheet on that region.
    @MainActor
    func testSorenessModePaintsTheFigureAndATapOpensTheSheet() throws {
        let email = "soremap+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger",
        ])
        try Server.post("/api/v1/soreness/quads", token: token, body: ["severity": 3], method: "PUT")
        try Server.post("/api/v1/soreness/upper_back", token: token, body: ["severity": 1], method: "PUT")

        let app = launchSignedIn(email: email, password: password)
        let figure = app.descendants(matching: .any).matching(identifier: "body-map").firstMatch
        dismissSavePassword(app)
        for _ in 0..<12 where !(figure.exists && figure.isHittable) {
            answerSavePassword(app)
            app.swipeUp()
            usleep(400_000)
        }
        XCTAssertTrue(figure.exists, "no body figure on Today")
        sleep(2)
        attach(app, "00-training-mode")

        let soreness = app.segmentedControls["body-mode"].buttons["Soreness"]
        XCTAssertTrue(soreness.waitForExistence(timeout: 10), "no Training | Soreness switch")
        soreness.tap()
        sleep(2)
        attach(app, "01-soreness-mode")
        XCTAssertTrue((figure.value as? String ?? "").contains("Quads"), "figure value: \(figure.value ?? "nil")")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "soreness-strip").firstMatch.exists, "no soreness strip")

        let sheet = app.navigationBars["Body"]
        for dx in [0.45, 0.5, 0.4, 0.55] where !sheet.exists {
            figure.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.62)).tap()
            _ = sheet.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(sheet.exists, "a tap on the sore thigh opened nothing")
        attach(app, "02-sheet")
    }
}
