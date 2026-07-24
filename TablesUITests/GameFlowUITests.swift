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

        // Setup: nothing is preselected, so pick a table to enable Start.
        let table = app.buttons["setup.table.3"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.tap()

        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Game
        let problem = app.staticTexts["game.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("\u{00D7}"), "the problem should use ×, got \(problem.label)")
        XCTAssertTrue(app.staticTexts["game.status"].exists)

        // Answer one question correctly. Under `-uiTesting` the countdown is
        // capped to a few seconds, so the clock then runs out on its own and
        // carries us to Results — there is no longer an End button.
        let factors = problem.label
            .components(separatedBy: "\u{00D7}")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        XCTAssertEqual(factors.count, 2, "expected two factors in '\(problem.label)'")
        let correctAnswer = factors[0] * factors[1]

        let option = app.buttons["game.option.\(correctAnswer)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()

        // Results (arrives when the capped clock expires).
        XCTAssertTrue(app.staticTexts["results.score"].waitForExistence(timeout: 15))
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
