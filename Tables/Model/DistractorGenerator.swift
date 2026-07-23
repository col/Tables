import Foundation

/// Builds the option set for multiple choice.
///
/// Distractors are drawn from two families of realistic mistake: an off-by-a-few
/// slip, and a neighbouring multiple of the same table. A random spread of
/// unrelated numbers would be trivially dismissable and teach nothing.
nonisolated enum DistractorGenerator {

    /// Bounded so a fact with few plausible neighbours cannot spin forever.
    private static let maxAttempts = 80

    static func options(
        for fact: Fact,
        count: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [Int] {
        let answer = fact.answer
        var values: Set<Int> = [answer]

        var attempts = 0
        while values.count < count && attempts < maxAttempts {
            attempts += 1
            let drift = Int.random(in: 0...6, using: &rng) - 3
            let step = Bool.random(using: &rng) ? 1 : fact.a
            let candidate = answer + drift * step
            if candidate > 0 && candidate != answer {
                values.insert(candidate)
            }
        }

        // Small answers can exhaust the plausible neighbours; pad upward so the
        // grid is never short.
        var padding = 1
        while values.count < count {
            values.insert(answer + padding)
            padding += 1
        }

        return values.shuffled(using: &rng)
    }
}
