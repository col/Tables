import Foundation

/// One multiplication fact. `a` is the table, `b` the multiplicand.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated struct Fact: Hashable, Sendable, Identifiable {
    let a: Int
    let b: Int

    var id: String { key }
    var answer: Int { a * b }

    /// Stable storage key, e.g. "7x8".
    var key: String { "\(a)x\(b)" }

    /// Uses U+00D7, never a lowercase letter x.
    var display: String { "\(a) \u{00D7} \(b)" }

    /// The answer shown inline beside the question once revealed, e.g. "= 56".
    var answerReveal: String { "= \(answer)" }
}
