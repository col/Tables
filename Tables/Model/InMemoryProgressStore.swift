import Foundation

/// Used by tests and SwiftUI previews. Behaviour must match
/// `SwiftDataProgressStore` exactly — `ProgressStoreTests` runs the same suite
/// against both.
@MainActor
final class InMemoryProgressStore: ProgressRecording {
    private var stats: [String: FactStat] = [:]
    /// Each run keeps its own configKey alongside it rather than being looked
    /// up by date. Two runs recorded at the same `Date` (different configs,
    /// or a caller reusing a timestamp) are common in tests and would collide
    /// in a `[Date: String]` side table, silently reassigning one run's
    /// config to another's.
    private var runs: [(configKey: String, record: RunRecord)] = []

    init() {}

    private func stat(for fact: Fact) -> FactStat {
        if let existing = stats[fact.key] { return existing }
        let created = FactStat(fact: fact)
        stats[fact.key] = created
        return created
    }

    func history() -> [String: FactHistory] {
        stats.mapValues(\.history)
    }

    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date) {
        stat(for: fact).recordCorrect(millis: millis, at: date)
    }

    func recordIncorrect(_ fact: Fact, at date: Date) {
        stat(for: fact).recordIncorrect(at: date)
    }

    func recordRun(configKey: String, score: Int, answered: Int, at date: Date) {
        runs.append((configKey, RunRecord(score: score, answered: answered, date: date)))
    }

    func runs(forConfigKey key: String) -> [RunRecord] {
        runs
            .filter { $0.configKey == key }
            .map(\.record)
            .sorted { $0.date > $1.date }
    }
}
