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
        // `stat(for:)` can, on a transient fetch failure, insert a second
        // `FactStat` sharing a key that already exists. That must not turn
        // into a crash here: `Dictionary(uniqueKeysWithValues:)` traps on a
        // duplicate key, which would let one bad read take down an unrelated
        // call days later. Keep whichever stat has more attempts recorded —
        // it carries more of the child's real history.
        return Dictionary(
            stats.map { ($0.key, $0.history) },
            uniquingKeysWith: { existing, incoming in
                existing.attempts >= incoming.attempts ? existing : incoming
            }
        )
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
        do {
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
            // Fetch succeeded and found nothing: genuinely a new fact.
        } catch {
            // The fetch itself failed — indistinguishable here from "not
            // found", but it is not the same thing. This store must stay
            // non-throwing (the caller, mid-game, cannot handle an error),
            // so the deliberate choice is to fail open: fall through and
            // create a fresh `FactStat` rather than losing the answer the
            // child just gave. If a stat with this key already exists in
            // the store, that can leave two rows sharing a key; `history()`
            // is written to tolerate that rather than trap on it.
        }
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
