import Testing
@testable import Tables

struct MasteryTests {

    @Test("a fact never attempted is Not yet")
    func unseenIsNotYet() {
        #expect(Mastery.level(for: .unseen) == .notYet)
        #expect(Mastery.level(for: FactHistory(attempts: 0, correctCount: 0, averageMillis: 0)) == .notYet)
    }

    @Test("three fast correct answers earn Mastered")
    func threeFastCorrectIsMastered() {
        let history = FactHistory(attempts: 3, correctCount: 3, averageMillis: 2999)
        #expect(Mastery.level(for: history) == .mastered)
    }

    @Test("two fast correct answers is not yet Mastered")
    func twoCorrectIsNotEnough() {
        let history = FactHistory(attempts: 2, correctCount: 2, averageMillis: 1200)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("three correct but slow is Getting there")
    func slowIsNotMastered() {
        let history = FactHistory(attempts: 3, correctCount: 3, averageMillis: 3000)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("attempted but never correct is Getting there, not Not yet")
    func attemptedButWrongIsGettingThere() {
        let history = FactHistory(attempts: 5, correctCount: 0, averageMillis: 0)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("the first correct answer sets the average outright")
    func firstCorrectSeedsTheAverage() {
        let updated = Mastery.updatedAverage(current: 0, correctCount: 0, latestMillis: 2400)
        #expect(updated == 2400)
    }

    @Test("later answers blend in at alpha 0.3, so the average tracks improvement")
    func laterAnswersBlend() {
        let updated = Mastery.updatedAverage(current: 4000, correctCount: 1, latestMillis: 2000)
        #expect(abs(updated - 3400) < 0.0001)
    }

    @Test("a run of fast answers pulls a slow average below the mastery bar")
    func improvementIsReflected() {
        var average = 6000.0
        for index in 0..<8 {
            average = Mastery.updatedAverage(current: average, correctCount: index + 1, latestMillis: 1500)
        }
        #expect(average < Mastery.masteryThresholdMillis)
    }
}
