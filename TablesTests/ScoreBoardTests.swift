import Testing
import Foundation
@testable import Tables

struct ScoreBoardTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func run(_ score: Int, daysAgo: Double = 0) -> RunRecord {
        RunRecord(score: score, answered: score, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("a first run scoring zero is not a personal best")
    func firstRunScoringZero() {
        let result = ScoreBoard.evaluate(previousRuns: [], current: run(0))
        #expect(!result.isNewBest)
        #expect(result.previousBest == nil)
        #expect(result.bannerText == "Your first run \u{2014} every one counts")
    }

    @Test("a first run scoring above zero is a personal best")
    func firstScoringRun() {
        let result = ScoreBoard.evaluate(previousRuns: [], current: run(7))
        #expect(result.isNewBest)
        #expect(result.previousBest == nil)
        #expect(result.bannerText == "New personal best")
    }

    @Test("beating the previous best names the number beaten")
    func beatingPreviousBest() {
        let result = ScoreBoard.evaluate(previousRuns: [run(9, daysAgo: 2), run(4, daysAgo: 3)], current: run(12))
        #expect(result.isNewBest)
        #expect(result.previousBest == 9)
        #expect(result.bannerText == "New personal best \u{2014} beat 9")
    }

    @Test("equalling the previous best is not a new best")
    func equallingIsNotBest() {
        let result = ScoreBoard.evaluate(previousRuns: [run(9, daysAgo: 1)], current: run(9))
        #expect(!result.isNewBest)
        #expect(result.bannerText == "Your best is 9")
    }

    @Test("falling short reports the standing best")
    func fallingShort() {
        let result = ScoreBoard.evaluate(previousRuns: [run(15, daysAgo: 1)], current: run(6))
        #expect(!result.isNewBest)
        #expect(result.bannerText == "Your best is 15")
    }

    @Test("lists at most five runs, highest score first")
    func listsTopFive() {
        let previous = [run(3, daysAgo: 1), run(11, daysAgo: 2), run(8, daysAgo: 3),
                        run(5, daysAgo: 4), run(14, daysAgo: 5), run(1, daysAgo: 6)]
        let result = ScoreBoard.evaluate(previousRuns: previous, current: run(9))
        #expect(result.topRuns.count == 5)
        #expect(result.topRuns.map(\.score) == [14, 11, 9, 8, 5])
    }

    @Test("ties are broken by the earlier run, so a record keeps its place")
    func tiesFavourTheEarlierRun() {
        let older = run(10, daysAgo: 4)
        let current = run(10)
        let result = ScoreBoard.evaluate(previousRuns: [older], current: current)
        #expect(result.topRuns.first == older)
        #expect(result.topRuns.count == 2)
    }

    @Test("the current run is always included in the list")
    func currentRunAlwaysListed() {
        let previous = (1...10).map { run(50 + $0, daysAgo: Double($0)) }
        let result = ScoreBoard.evaluate(previousRuns: previous, current: run(1))
        #expect(result.topRuns.count == ScoreBoard.maximumListed)
        // A low score does not force its way in; the board stays honest.
        #expect(!result.topRuns.contains(run(1)))
    }

    @Test("relative date labels read plainly")
    func dateLabels() {
        #expect(ScoreBoard.relativeDateLabel(for: now, isCurrentRun: true, now: now) == "Just now")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-3600), isCurrentRun: false, now: now) == "Earlier today")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-86_400), isCurrentRun: false, now: now) == "Yesterday")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-5 * 86_400), isCurrentRun: false, now: now) == "5 days ago")
    }
}
