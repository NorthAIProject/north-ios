import XCTest

/// Horizon against a local server: twelve weeks of two lifts and six of
/// weigh-ins give a forecast; the day is moved with the slider, and a what-if
/// is switched on. Screenshots of each stage are attached.
final class HorizonUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testForecastScrubsAndTakesAWhatIf() throws {
        let email = "horizon+\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "Correct-horse-9"
        let token = try Server.signUp(email: email, password: password)
        try Server.post("/api/v1/onboarding", token: token, body: [
            "focusAreas": ["fitness"], "coachingStyle": "direct", "nearTermGoal": "Get stronger"
        ])
        try seedHistory(token: token)
        // What would otherwise open over the app: the AI data-sharing
        // question, and the celebration for medals the seeded sets earned.
        try Server.post("/api/v1/ai-consent", token: token, body: ["decision": "granted"], method: "PUT")
        let unseen = try Server.get("/api/v1/awards/unseen", token: token)
        for award in unseen["awards"] as? [[String: Any]] ?? [] {
            guard let id = award["id"] as? String else { continue }
            try Server.post("/api/v1/awards/\(id)/seen", token: token, body: [:])
        }
        let forecast = try Server.get("/api/v1/horizon", token: token)
        XCTAssertEqual(forecast["status"] as? String, "ready", "the seeded history did not make a forecast")
        XCTAssertEqual(forecast["hasPlan"] as? Bool, true)

        let app = launchSignedIn(email: email, password: password)
        dismissSavePassword(app)
        openTab(app, "More")
        tap(app.buttons["Horizon"])
        XCTAssertTrue(app.navigationBars["Horizon"].waitForExistence(timeout: 20), "Horizon did not open")

        let slider = app.sliders["Day to look at"]
        XCTAssertTrue(slider.waitForExistence(timeout: 30), "no forecast on screen")
        XCTAssertEqual(slider.value as? String, "Today")
        XCTAssertTrue(app.staticTexts["Barbell Squat"].exists, "the squat has no row")
        XCTAssertTrue(app.staticTexts["Est. 1RM"].firstMatch.exists, "a lift's number is not named as an estimated max")
        sleep(2) // the figure loads its model
        attach(app, "00-today")

        slider.adjust(toNormalizedSliderPosition: 0.75)
        let ahead = slider.value as? String ?? ""
        XCTAssertTrue(ahead.hasPrefix("In "), "the slider did not move the day: \(ahead)")
        sleep(1)
        attach(app, "01-weeks-ahead")

        app.swipeUp()
        attach(app, "02-ranges-and-what-ifs")
        let fourOff = app.buttons["4 wk off"]
        tap(fourOff)
        XCTAssertTrue(app.buttons["Plain Forecast"].waitForExistence(timeout: 20), "the what-if did not load")
        XCTAssertTrue(fourOff.isSelected, "4 wk off does not read as chosen")
        attach(app, "03-four-weeks-off")
        app.swipeDown()
        // The what-if keeps the day that was being looked at.
        XCTAssertEqual(app.sliders["Day to look at"].value as? String, ahead)
        sleep(1)
        attach(app, "04-four-weeks-off-figure")
    }

    /// Two lifts twice a week for twelve weeks, creeping up; six weeks of
    /// morning weights drifting down; and a plan that keeps both lifts going.
    /// Loads stay under 100 kg: a heavier set earns the Century award.
    private func seedHistory(token: String) throws {
        try Server.post("/api/v1/training/import", token: token, body: [
            "name": "Horizon plan",
            "days": [
                ["label": "Lower", "weekday": "Monday", "exercises": [
                    ["name": "Barbell Squat", "sets": 3, "reps": "4-6", "load": "", "notes": "", "flags": [String]()]
                ]],
                ["label": "Upper", "weekday": "Thursday", "exercises": [
                    ["name": "Dumbbell Bench Press", "sets": 3, "reps": "5", "load": "", "notes": "", "flags": [String]()]
                ]]
            ],
            "unparsed": [String]()
        ])
        let stamp = ISO8601DateFormatter()
        let day: TimeInterval = 24 * 3600
        for session in 0..<24 {
            let at = stamp.string(from: Date.now.addingTimeInterval(-(84 - Double(session) * 3.5) * day))
            let wobble: Double = [0, 2.5, -2.5, 0][session % 4]
            let lifts: [(String, Double)] = [("Barbell Squat", 60), ("Dumbbell Bench Press", 40)]
            for (name, start) in lifts {
                let kilos: Double = start + Double(session / 3) * 2.5 + wobble
                let set: [String: Any] = [
                    "exerciseName": name, "setNumber": 0, "weightKg": kilos, "reps": 5, "rir": 2, "performedAt": at
                ]
                for _ in 0..<3 {
                    try Server.post("/api/v1/lifts/sets", token: token, body: set)
                }
            }
        }
        var readings: [[String: Any]] = []
        for ago in 1...42 {
            let kilos: Double = 82 + Double(ago) * 0.05 + Double(ago % 3) * 0.2
            let at: String = stamp.string(from: Date.now.addingTimeInterval(-Double(ago) * day))
            let reading: [String: Any] = ["metric": "body_mass", "value": kilos, "unit": "kg", "startedAt": at]
            readings.append(reading)
        }
        try Server.post("/api/v1/health/samples", token: token, body: ["readings": readings, "workouts": [[String: Any]]()])
    }
}
