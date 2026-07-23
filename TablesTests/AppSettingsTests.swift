import Testing
import Foundation
@testable import Tables

@MainActor
struct AppSettingsTests {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a fresh install has sound and haptics on and six options")
    func defaults() {
        let settings = AppSettings(defaults: freshDefaults("test.defaults"))
        #expect(settings.soundEnabled)
        #expect(settings.hapticsEnabled)
        #expect(settings.multipleChoiceOptionCount == 6)
    }

    @Test("changes survive a relaunch")
    func changesPersist() {
        let defaults = freshDefaults("test.persist")
        let first = AppSettings(defaults: defaults)
        first.soundEnabled = false
        first.hapticsEnabled = false
        first.multipleChoiceOptionCount = 4

        let second = AppSettings(defaults: defaults)
        #expect(!second.soundEnabled)
        #expect(!second.hapticsEnabled)
        #expect(second.multipleChoiceOptionCount == 4)
    }

    @Test("an out-of-range option count falls back to six")
    func optionCountIsClamped() {
        let defaults = freshDefaults("test.clamp")
        defaults.set(9, forKey: "settings.multipleChoiceOptionCount")
        #expect(AppSettings(defaults: defaults).multipleChoiceOptionCount == 6)
    }

    @Test("only four and six are offered")
    func choices() {
        #expect(AppSettings.optionCountChoices == [4, 6])
    }
}
