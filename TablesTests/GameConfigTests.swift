import Testing
@testable import Tables

struct FactTests {

    @Test("a fact knows its answer, storage key and display string")
    func factBasics() {
        let fact = Fact(a: 7, b: 8)
        #expect(fact.answer == 56)
        #expect(fact.key == "7x8")
        #expect(fact.display == "7 × 8")
    }

    @Test("the display string uses the multiplication sign, never a letter x")
    func displayUsesMultiplicationSign() {
        #expect(Fact(a: 3, b: 4).display.contains("\u{00D7}"))
        #expect(!Fact(a: 3, b: 4).display.contains("x"))
    }
}

struct GameLengthTests {

    @Test("lengths produce stable keys for score-board scoping")
    func keys() {
        #expect(GameLength.seconds(60).key == "cd60")
        #expect(GameLength.questions(20).key == "rev20")
        #expect(GameLength.endless.key == "revEndless")
    }

    @Test("lengths summarise for the setup screen")
    func summaries() {
        #expect(GameLength.seconds(90).summary == "90 seconds")
        #expect(GameLength.questions(30).summary == "30 questions")
        #expect(GameLength.endless.summary == "Endless")
    }

    @Test("the option lists match the spec")
    func optionLists() {
        #expect(GameLength.countdownOptions == [.seconds(30), .seconds(60), .seconds(90), .seconds(120)])
        #expect(GameLength.revisionOptions == [
            .questions(10), .questions(20), .questions(30),
            .questions(40), .questions(50), .questions(60), .endless
        ])
    }
}

struct GameConfigTests {

    private func config(
        mode: GameMode = .countdown,
        tables: Set<Int> = [3, 6, 7, 8],
        answerMode: AnswerMode = .multipleChoice,
        length: GameLength = .seconds(60)
    ) -> GameConfig {
        GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
    }

    @Test("the config key sorts tables so selection order cannot fork a score board")
    func configKeyIsOrderIndependent() {
        let a = config(tables: [8, 3, 7, 6])
        let b = config(tables: [3, 6, 7, 8])
        #expect(a.configKey == b.configKey)
        #expect(a.configKey == "countdown|3-6-7-8|multipleChoice|cd60")
    }

    @Test("changing any dimension changes the config key")
    func configKeyIsSensitiveToEveryDimension() {
        let base = config().configKey
        #expect(config(mode: .revision, length: .questions(20)).configKey != base)
        #expect(config(tables: [3, 6, 7]).configKey != base)
        #expect(config(answerMode: .numberPad).configKey != base)
        #expect(config(length: .seconds(30)).configKey != base)
    }

    @Test("facts cover every multiplicand 1 through 12 for each selected table")
    func factsCoverTheGrid() {
        let facts = config(tables: [3, 7]).facts
        #expect(facts.count == 24)
        #expect(facts.allSatisfy { [3, 7].contains($0.a) })
        #expect(Set(facts.map(\.b)) == Set(1...12))
    }

    @Test("the tables summary reads as the design specifies")
    func tablesSummary() {
        #expect(config(tables: [7, 3]).tablesSummary == "×3  ×7")
        #expect(config(tables: Set(1...12)).tablesSummary == "All tables")
        #expect(config(tables: []).tablesSummary == "None chosen")
    }

    @Test("a config with no tables cannot start")
    func startability() {
        #expect(config().isStartable)
        #expect(!config(tables: []).isStartable)
    }
}
