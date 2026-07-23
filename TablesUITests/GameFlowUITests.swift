import XCTest

final class GameFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testCountdownGameReachesResults() throws {
        // Home
        let countdown = app.buttons["home.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 10))
        countdown.tap()

        // Setup: a single table and the shortest run keeps the test quick.
        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Game
        let problem = app.staticTexts["game.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("\u{00D7}"), "the problem should use ×, got \(problem.label)")
        XCTAssertTrue(app.staticTexts["game.status"].exists)

        // Answer correctly, then end the run early rather than waiting out the
        // clock. A wrong tap in Countdown mode just retries the same
        // question and never increments `answered`, which would make
        // `endEarly` report `.abandoned` and send us back Home instead of to
        // Results — so pick the option that actually matches the problem.
        let factors = problem.label
            .components(separatedBy: "\u{00D7}")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(factors.count, 2, "expected two factors in '\(problem.label)'")
        let correctAnswer = factors[0] * factors[1]

        let option = app.buttons["game.option.\(correctAnswer)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()

        let end = app.buttons["game.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()

        // Results
        XCTAssertTrue(app.staticTexts["results.score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["results.playAgain"].exists)
    }

    func testProgressScreenOpensFromHome() throws {
        let progress = app.buttons["home.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        XCTAssertTrue(app.staticTexts["Your tables"].waitForExistence(timeout: 5))
    }

    func testSettingsSheetOpensAndCloses() throws {
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
    }
}
