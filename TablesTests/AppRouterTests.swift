import Testing
import Foundation
@testable import Tables

@MainActor
struct AppRouterTests {

    private func summary(score: Int) -> GameSession.Summary {
        GameSession.Summary(
            config: .default,
            score: score,
            answered: score,
            board: ScoreBoard.evaluate(
                previousRuns: [],
                current: RunRecord(score: score, answered: score, date: Date(timeIntervalSince1970: 0))
            )
        )
    }

    @Test("home starts with an empty path")
    func startsAtHome() {
        #expect(AppRouter().path.isEmpty)
    }

    @Test("opening setup pushes one screen")
    func openSetup() {
        let router = AppRouter()
        router.openSetup(.revision)
        #expect(router.path == [.setup(.revision)])
    }

    @Test("results replaces the game, so Back never returns into a dead game")
    func resultsReplacesTheGame() {
        let router = AppRouter()
        router.openSetup(.countdown)
        router.startGame(.default)
        #expect(router.path == [.setup(.countdown), .game(.default)])

        router.showResults(summary(score: 9))
        #expect(router.path == [.results])
        #expect(router.summary?.score == 9)
    }

    @Test("playing again returns to the game with the same configuration")
    func playAgainReusesTheConfig() {
        let router = AppRouter()
        router.startGame(.default)
        router.showResults(summary(score: 3))
        router.playAgain()
        #expect(router.path == [.game(.default)])
    }

    @Test("playing again with no summary is a no-op rather than a crash")
    func playAgainWithoutSummary() {
        let router = AppRouter()
        router.playAgain()
        #expect(router.path.isEmpty)
    }

    @Test("going home clears the path and the stale summary")
    func goHomeClearsEverything() {
        let router = AppRouter()
        router.startGame(.default)
        router.showResults(summary(score: 4))
        router.goHome()
        #expect(router.path.isEmpty)
        #expect(router.summary == nil)
    }

    @Test("progress is reachable from home")
    func openProgress() {
        let router = AppRouter()
        router.openProgress()
        #expect(router.path == [.progress])
    }
}
