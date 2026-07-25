import Testing
import Foundation
@testable import Tables

@MainActor
struct SetupModelTests {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("countdown opens on the tables section with nothing preselected")
    func countdownDefaults() {
        let model = SetupModel(mode: .countdown, defaults: freshDefaults("setup.cd"))
        #expect(model.openSection == .tables)
        #expect(model.tables.isEmpty)
        #expect(!model.config.isStartable, "Start should wait until a table is chosen")
        #expect(model.answerMode == .multipleChoice)
        #expect(model.length == .seconds(60))
        #expect(model.lengthOptions == GameLength.countdownOptions)
    }

    @Test("revision defaults to twenty questions")
    func revisionDefaults() {
        let model = SetupModel(mode: .revision, defaults: freshDefaults("setup.rev"))
        #expect(model.length == .questions(20))
        #expect(model.lengthOptions == GameLength.revisionOptions)
    }

    @Test("tapping a table toggles it in and out")
    func togglingTables() {
        let model = SetupModel(mode: .countdown, defaults: freshDefaults("setup.toggle"))
        model.toggle(table: 5)
        #expect(model.tables.contains(5))
        model.toggle(table: 5)
        #expect(!model.tables.contains(5))
    }

    @Test("select all fills every table, then clears them")
    func selectAndClearAll() {
        let model = SetupModel(mode: .countdown, defaults: freshDefaults("setup.all"))
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
        let model = SetupModel(mode: .countdown, defaults: freshDefaults("setup.sections"))
        model.toggle(section: .answerMode)
        #expect(model.openSection == .answerMode)
        model.toggle(section: .length)
        #expect(model.openSection == .length)
        model.toggle(section: .length)
        #expect(model.openSection == nil)
    }

    @Test("the model produces the config the game will be played with")
    func producesConfig() {
        let model = SetupModel(mode: .revision, defaults: freshDefaults("setup.config"))
        model.tables = [2, 4]
        model.answerMode = .numberPad
        model.length = .endless

        #expect(model.config == GameConfig(
            mode: .revision, tables: [2, 4], answerMode: .numberPad, length: .endless
        ))
    }

    @Test("remembered selections are the defaults next time")
    func remembersSelections() {
        let defaults = freshDefaults("setup.remember")

        let first = SetupModel(mode: .countdown, defaults: defaults)
        first.tables = [3, 7, 9]
        first.answerMode = .numberPad
        first.length = .seconds(90)
        first.rememberSelections()

        let second = SetupModel(mode: .countdown, defaults: defaults)
        #expect(second.tables == [3, 7, 9])
        #expect(second.answerMode == .numberPad)
        #expect(second.length == .seconds(90))
    }

    @Test("tables and answer mode carry across modes, length is per mode")
    func tablesShareButLengthIsPerMode() {
        let defaults = freshDefaults("setup.crossmode")

        let countdown = SetupModel(mode: .countdown, defaults: defaults)
        countdown.tables = [2, 5]
        countdown.answerMode = .numberPad
        countdown.length = .seconds(30)
        countdown.rememberSelections()

        // Revision inherits the shared tables and answer mode, but keeps its own
        // default length because none has been saved for it yet.
        let revision = SetupModel(mode: .revision, defaults: defaults)
        #expect(revision.tables == [2, 5])
        #expect(revision.answerMode == .numberPad)
        #expect(revision.length == .questions(20))

        revision.length = .endless
        revision.rememberSelections()

        // The Revision length does not leak back into Countdown.
        let countdownAgain = SetupModel(mode: .countdown, defaults: defaults)
        #expect(countdownAgain.length == .seconds(30))
    }

    @Test("a stored length invalid for the mode falls back to the default")
    func ignoresLengthFromOtherMode() {
        let defaults = freshDefaults("setup.badlength")
        // A revision length wrongly stored under the countdown key.
        let data = try! JSONEncoder().encode(GameLength.questions(40))
        defaults.set(data, forKey: "setup.length.countdown")

        let model = SetupModel(mode: .countdown, defaults: defaults)
        #expect(model.length == .seconds(60))
    }

    @Test("voice is offered only when supported")
    func voiceGating() {
        let defaults = UserDefaults(suiteName: "voice.gating.\(UUID().uuidString)")!
        let supported = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: true)
        #expect(supported.availableAnswerModes.contains(.voice))
        let unsupported = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: false)
        #expect(unsupported.availableAnswerModes.contains(.voice) == false)
    }

    @Test("a stored voice mode falls back when unsupported")
    func voiceFallback() {
        let defaults = UserDefaults(suiteName: "voice.fallback.\(UUID().uuidString)")!
        defaults.set(AnswerMode.voice.rawValue, forKey: "setup.answerMode")
        let model = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: false)
        #expect(model.answerMode == .multipleChoice)
    }

    @Test("a stored voice mode is kept when supported")
    func voiceKept() {
        let defaults = UserDefaults(suiteName: "voice.kept.\(UUID().uuidString)")!
        defaults.set(AnswerMode.voice.rawValue, forKey: "setup.answerMode")
        let model = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: true)
        #expect(model.answerMode == .voice)
    }
}
