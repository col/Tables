import Testing
@testable import Tables

/// Deterministic generator so option sets are reproducible in tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

struct DistractorGeneratorTests {

    @Test("returns exactly the requested number of options", arguments: [4, 6])
    func returnsRequestedCount(_ count: Int) {
        var rng = SeededRandom(seed: 42)
        for a in 1...12 {
            for b in 1...12 {
                let options = DistractorGenerator.options(
                    for: Fact(a: a, b: b), count: count, using: &rng
                )
                #expect(options.count == count, "\(a)×\(b) produced \(options.count) options")
            }
        }
    }

    @Test("always includes the correct answer", arguments: [4, 6])
    func alwaysIncludesTheAnswer(_ count: Int) {
        var rng = SeededRandom(seed: 7)
        for a in 1...12 {
            for b in 1...12 {
                let fact = Fact(a: a, b: b)
                let options = DistractorGenerator.options(for: fact, count: count, using: &rng)
                #expect(options.contains(fact.answer), "\(fact.key) omitted its own answer")
            }
        }
    }

    @Test("all options are unique and positive")
    func optionsAreUniqueAndPositive() {
        var rng = SeededRandom(seed: 99)
        for a in 1...12 {
            for b in 1...12 {
                let options = DistractorGenerator.options(
                    for: Fact(a: a, b: b), count: 6, using: &rng
                )
                #expect(Set(options).count == options.count, "\(a)×\(b) had duplicates: \(options)")
                #expect(options.allSatisfy { $0 > 0 }, "\(a)×\(b) had non-positive: \(options)")
            }
        }
    }

    @Test("copes with the smallest fact, where few smaller distractors exist")
    func handlesSmallestFact() {
        var rng = SeededRandom(seed: 1)
        let options = DistractorGenerator.options(for: Fact(a: 1, b: 1), count: 6, using: &rng)
        #expect(options.count == 6)
        #expect(options.contains(1))
        #expect(Set(options).count == 6)
        #expect(options.allSatisfy { $0 > 0 })
    }

    @Test("copes with the largest fact")
    func handlesLargestFact() {
        var rng = SeededRandom(seed: 2)
        let options = DistractorGenerator.options(for: Fact(a: 12, b: 12), count: 6, using: &rng)
        #expect(options.count == 6)
        #expect(options.contains(144))
    }

    @Test("does not always place the answer in the same slot")
    func answerPositionVaries() {
        var indices = Set<Int>()
        for seed in UInt64(1)...UInt64(40) {
            var rng = SeededRandom(seed: seed)
            let fact = Fact(a: 7, b: 8)
            let options = DistractorGenerator.options(for: fact, count: 6, using: &rng)
            indices.insert(options.firstIndex(of: fact.answer)!)
        }
        #expect(indices.count > 1, "the answer always landed in the same position")
    }
}
