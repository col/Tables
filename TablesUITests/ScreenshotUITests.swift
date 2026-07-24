import XCTest

// SnapshotHelper declares `setupSnapshot`/`snapshot` as @MainActor, so the
// test case that calls them must be @MainActor too.
@MainActor
final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        // -uiTesting caps the countdown and disables persistence (see SetupModel/GameView).
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    func testCaptureScreens() throws {
        // 01 Home
        let countdown = app.buttons["home.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 15))
        snapshot("01Home")

        // 02 Setup
        countdown.tap()
        let table = app.buttons["setup.table.3"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.tap()
        snapshot("02Setup")

        // 03 Game
        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let problem = app.staticTexts["game.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        snapshot("03Game")

        // 04 Results — answer correctly, then the capped clock carries us to Results.
        let factors = problem.label
            .components(separatedBy: "\u{00D7}")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if factors.count == 2 {
            let option = app.buttons["game.option.\(factors[0] * factors[1])"]
            if option.waitForExistence(timeout: 5) { option.tap() }
        }
        let score = app.staticTexts["results.score"]
        XCTAssertTrue(score.waitForExistence(timeout: 20))
        snapshot("04Results")
    }

    func testCaptureProgress() throws {
        // 05 Progress
        let progress = app.buttons["home.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        progress.tap()
        XCTAssertTrue(app.staticTexts["Your tables"].waitForExistence(timeout: 10))
        snapshot("05Progress")
    }
}
