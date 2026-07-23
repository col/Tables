import Foundation

/// Chooses the next fact to ask.
///
/// Countdown is uniform — it is a speed test, not a teaching tool. Revision
/// serves every unseen fact first so a session cannot skip a whole table, then
/// weights by how long each fact has been taking.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated struct QuestionPicker: Sendable {
    let facts: [Fact]
    let mode: GameMode

    /// Even a fact answered instantly should still come round occasionally.
    static let minimumWeight: Double = 400

    init(facts: [Fact], mode: GameMode) {
        self.facts = facts
        self.mode = mode
    }

    func next(
        history: [String: FactHistory],
        previous: Fact?,
        using rng: inout some RandomNumberGenerator
    ) -> Fact {
        let eligible = facts.count > 1 ? facts.filter { $0 != previous } : facts
        guard !eligible.isEmpty else { return facts[0] }

        switch mode {
        case .countdown:
            return eligible.randomElement(using: &rng) ?? eligible[0]

        case .revision:
            let unseen = eligible.filter { (history[$0.key] ?? .unseen).isUnseen }
            if !unseen.isEmpty {
                return unseen.randomElement(using: &rng) ?? unseen[0]
            }
            return weightedPick(from: eligible, history: history, using: &rng)
        }
    }

    private func weightedPick(
        from candidates: [Fact],
        history: [String: FactHistory],
        using rng: inout some RandomNumberGenerator
    ) -> Fact {
        let weights = candidates.map { fact in
            max(Self.minimumWeight, (history[fact.key] ?? .unseen).averageMillis)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates[0] }

        var target = Double.random(in: 0..<total, using: &rng)
        for (fact, weight) in zip(candidates, weights) {
            target -= weight
            if target <= 0 { return fact }
        }
        return candidates[candidates.count - 1]
    }
}
