import Testing
@testable import Tables

@MainActor
struct SetupModelTests {

    @Test("countdown opens on the tables section with sensible defaults")
    func countdownDefaults() {
        let model = SetupModel(mode: .countdown)
        #expect(model.openSection == .tables)
        #expect(model.tables == [3, 6, 7, 8])
        #expect(model.answerMode == .multipleChoice)
        #expect(model.length == .seconds(60))
        #expect(model.lengthOptions == GameLength.countdownOptions)
    }

    @Test("revision defaults to twenty questions")
    func revisionDefaults() {
        let model = SetupModel(mode: .revision)
        #expect(model.length == .questions(20))
        #expect(model.lengthOptions == GameLength.revisionOptions)
    }

    @Test("tapping a table toggles it in and out")
    func togglingTables() {
        let model = SetupModel(mode: .countdown)
        model.toggle(table: 5)
        #expect(model.tables.contains(5))
        model.toggle(table: 5)
        #expect(!model.tables.contains(5))
    }

    @Test("select all fills every table, then clears them")
    func selectAndClearAll() {
        let model = SetupModel(mode: .countdown)
        #expect(model.selectAllLabel == "Select all")

        model.toggleAll()
        #expect(model.tables == GameConfig.allTables)
        #expect(model.allSelected)
        #expect(model.selectAllLabel == "Clear all")

        model.toggleAll()
        #expect(model.tables.isEmpty)
        #expect(!model.config.isStartable)
    }

    @Test("only one section is open at a time, and tapping the open one closes it")
    func sectionsAreExclusive() {
        let model = SetupModel(mode: .countdown)
        model.toggle(section: .answerMode)
        #expect(model.openSection == .answerMode)
        model.toggle(section: .length)
        #expect(model.openSection == .length)
        model.toggle(section: .length)
        #expect(model.openSection == nil)
    }

    @Test("the model produces the config the game will be played with")
    func producesConfig() {
        let model = SetupModel(mode: .revision)
        model.tables = [2, 4]
        model.answerMode = .numberPad
        model.length = .endless

        #expect(model.config == GameConfig(
            mode: .revision, tables: [2, 4], answerMode: .numberPad, length: .endless
        ))
    }
}
