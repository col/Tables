import Foundation
import SwiftData

@MainActor
final class SwiftDataProgressStore: ProgressRecording {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func history() -> [String: FactHistory] {
        let stats = (try? context.fetch(FetchDescriptor<FactStat>())) ?? []
        return Dictionary(uniqueKeysWithValues: stats.map { ($0.key, $0.history) })
    }

    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date) {
        stat(for: fact).recordCorrect(millis: millis, at: date)
        save()
    }

    func recordIncorrect(_ fact: Fact, at date: Date) {
        stat(for: fact).recordIncorrect(at: date)
        save()
    }

    func recordRun(configKey: String, score: Int, answered: Int, at date: Date) {
        context.insert(GameRun(configKey: configKey, score: score, answered: answered, date: date))
        save()
    }

    func runs(forConfigKey key: String) -> [RunRecord] {
        let descriptor = FetchDescriptor<GameRun>(
            predicate: #Predicate { $0.configKey == key },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.record)
    }

    private func stat(for fact: Fact) -> FactStat {
        let key = fact.key
        var descriptor = FetchDescriptor<FactStat>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = FactStat(fact: fact)
        context.insert(created)
        return created
    }

    /// Progress data is worth nothing if losing a single write crashes a
    /// child's game, so a failed save is swallowed rather than thrown.
    private func save() {
        try? context.save()
    }
}
