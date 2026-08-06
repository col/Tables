import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let optionCountChoices = [4, 6]

    private static let soundKey = "settings.soundEnabled"
    private static let hapticsKey = "settings.hapticsEnabled"
    private static let optionCountKey = "settings.multipleChoiceOptionCount"
    private static let voiceSpeedKey = "settings.voiceSpeed"

    @ObservationIgnored private let defaults: UserDefaults

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundKey) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }

    var multipleChoiceOptionCount: Int {
        didSet { defaults.set(multipleChoiceOptionCount, forKey: Self.optionCountKey) }
    }

    var voiceSpeed: VoiceSpeed {
        didSet { defaults.set(voiceSpeed.rawValue, forKey: Self.voiceSpeedKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` distinguishes "off" from "never set".
        self.soundEnabled = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        let stored = defaults.object(forKey: Self.optionCountKey) as? Int ?? 6
        self.multipleChoiceOptionCount = Self.optionCountChoices.contains(stored) ? stored : 6
        let storedSpeed = defaults.object(forKey: Self.voiceSpeedKey) as? Int
        self.voiceSpeed = storedSpeed.flatMap(VoiceSpeed.init(rawValue:)) ?? .normal
    }
}
