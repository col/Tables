import Foundation

/// The only surface `GameSession` needs from persistence. Keeping it this
/// narrow is what lets a whole game be played out in a unit test.
@MainActor
protocol ProgressRecording: AnyObject {
    func history() -> [String: FactHistory]
    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date)
    func recordIncorrect(_ fact: Fact, at date: Date)
    func recordRun(configKey: String, score: Int, answered: Int, at date: Date)
    func runs(forConfigKey key: String) -> [RunRecord]
}

extension ProgressRecording {
    func masteryLevels() -> [String: MasteryLevel] {
        history().mapValues(Mastery.level(for:))
    }
}
