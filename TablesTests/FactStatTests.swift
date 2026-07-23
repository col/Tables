import Testing
import Foundation
@testable import Tables

struct FactStatTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a new stat starts unseen")
    func newStatIsUnseen() {
        let stat = FactStat(fact: Fact(a: 7, b: 8))
        #expect(stat.key == "7x8")
        #expect(stat.a == 7)
        #expect(stat.b == 8)
        #expect(stat.history == .unseen)
        #expect(Mastery.level(for: stat.history) == .notYet)
    }

    @Test("the first correct answer seeds the average outright")
    func firstCorrectSeedsAverage() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 2200, at: start)
        #expect(stat.attempts == 1)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 2200)
        #expect(stat.lastAnsweredAt == start)
    }

    @Test("later correct answers blend into the moving average")
    func laterCorrectBlends() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 4000, at: start)
        stat.recordCorrect(millis: 2000, at: start)
        #expect(abs(stat.averageMillis - 3400) < 0.0001)
        #expect(stat.correctCount == 2)
    }

    @Test("a correct answer with no timing still counts but leaves the average alone")
    func untimedCorrectLeavesAverageAlone() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 2000, at: start)
        stat.recordCorrect(millis: nil, at: start)
        #expect(stat.attempts == 2)
        #expect(stat.correctCount == 2)
        #expect(stat.averageMillis == 2000)
    }

    @Test("an untimed first correct answer does not fabricate an average")
    func untimedFirstCorrectStaysZero() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: nil, at: start)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 0)
        // No timing means no evidence of speed, so this must not read as mastery.
        stat.recordCorrect(millis: nil, at: start)
        stat.recordCorrect(millis: nil, at: start)
        #expect(Mastery.level(for: stat.history) == .gettingThere)
    }

    @Test("a wrong answer counts as an attempt but never touches the average")
    func wrongAnswerLeavesAverageAlone() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 1500, at: start)
        stat.recordIncorrect(at: start.addingTimeInterval(60))
        #expect(stat.attempts == 2)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 1500)
        #expect(stat.lastAnsweredAt == start.addingTimeInterval(60))
    }

    @Test("three fast correct answers reach Mastered through the model")
    func masteryThroughTheModel() {
        let stat = FactStat(fact: Fact(a: 5, b: 5))
        for _ in 0..<3 { stat.recordCorrect(millis: 1400, at: start) }
        #expect(Mastery.level(for: stat.history) == .mastered)
    }

    @Test("a run converts to a plain record")
    func runConvertsToRecord() {
        let run = GameRun(configKey: "countdown|3|numberPad|cd60", score: 11, answered: 14, date: start)
        #expect(run.record == RunRecord(score: 11, answered: 14, date: start))
    }
}
