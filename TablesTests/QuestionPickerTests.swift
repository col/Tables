import Testing
@testable import Tables

struct QuestionPickerTests {

    private let threeAndSeven = GameConfig(
        mode: .revision, tables: [3, 7], answerMode: .numberPad, length: .questions(10)
    ).facts

    @Test("never repeats the previous fact when others are available")
    func neverRepeatsConsecutively() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .countdown)
        var rng = SeededRandom(seed: 5)
        var previous: Fact? = nil
        for _ in 0..<200 {
            let next = picker.next(history: [:], previous: previous, using: &rng)
            #expect(next != previous)
            previous = next
        }
    }

    @Test("a single-fact pool returns that fact rather than deadlocking")
    func singleFactPool() {
        let only = Fact(a: 1, b: 1)
        let picker = QuestionPicker(facts: [only], mode: .revision)
        var rng = SeededRandom(seed: 3)
        #expect(picker.next(history: [:], previous: only, using: &rng) == only)
    }

    @Test("Revision serves every unseen fact before repeating any of them")
    func revisionExhaustsUnseenFirst() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .revision)
        var rng = SeededRandom(seed: 11)
        var history: [String: FactHistory] = [:]
        var served: [Fact] = []
        var previous: Fact? = nil

        for _ in 0..<threeAndSeven.count {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            served.append(fact)
            history[fact.key] = FactHistory(attempts: 1, correctCount: 1, averageMillis: 1500)
            previous = fact
        }

        #expect(Set(served) == Set(threeAndSeven), "some facts were never served")
        #expect(served.count == Set(served).count, "a fact repeated before coverage completed")
    }

    @Test("Revision favours slow facts once everything has been seen")
    func revisionWeightsSlowFacts() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .revision)
        let slow = Fact(a: 7, b: 8)
        var history: [String: FactHistory] = [:]
        for fact in threeAndSeven {
            let millis = fact == slow ? 9000.0 : 700.0
            history[fact.key] = FactHistory(attempts: 4, correctCount: 4, averageMillis: millis)
        }

        var rng = SeededRandom(seed: 21)
        var slowCount = 0
        var previous: Fact? = nil
        let draws = 3000
        for _ in 0..<draws {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            if fact == slow { slowCount += 1 }
            previous = fact
        }

        // 9000 against 23 facts at 700 gives roughly 36% of the total weight.
        let share = Double(slowCount) / Double(draws)
        #expect(share > 0.20, "slow fact was served only \(share) of the time")
        #expect(share < 0.55)
    }

    @Test("Countdown ignores history and stays close to uniform")
    func countdownIsUniform() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .countdown)
        let slow = Fact(a: 7, b: 8)
        var history: [String: FactHistory] = [:]
        for fact in threeAndSeven {
            let millis = fact == slow ? 9000.0 : 700.0
            history[fact.key] = FactHistory(attempts: 4, correctCount: 4, averageMillis: millis)
        }

        var rng = SeededRandom(seed: 33)
        var slowCount = 0
        var previous: Fact? = nil
        let draws = 3000
        for _ in 0..<draws {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            if fact == slow { slowCount += 1 }
            previous = fact
        }

        // Uniform over 24 facts is about 4.2%.
        let share = Double(slowCount) / Double(draws)
        #expect(share > 0.02 && share < 0.08, "countdown was not uniform: \(share)")
    }

    @Test("a floor stops very fast facts from being starved entirely")
    func weightFloorApplies() {
        let picker = QuestionPicker(facts: [Fact(a: 2, b: 2), Fact(a: 2, b: 3)], mode: .revision)
        var history: [String: FactHistory] = [:]
        history["2x2"] = FactHistory(attempts: 9, correctCount: 9, averageMillis: 1)
        history["2x3"] = FactHistory(attempts: 9, correctCount: 9, averageMillis: 400)

        var rng = SeededRandom(seed: 44)
        var fastCount = 0
        for _ in 0..<600 {
            // No previous, so both remain eligible on every draw.
            if picker.next(history: history, previous: nil, using: &rng) == Fact(a: 2, b: 2) {
                fastCount += 1
            }
        }
        #expect(fastCount > 200, "the 400ms floor was not applied")
    }
}
