import Foundation

/// One multiplication fact. `a` is the table, `b` the multiplicand.
struct Fact: Hashable, Sendable, Identifiable {
    let a: Int
    let b: Int

    var id: String { key }
    var answer: Int { a * b }

    /// Stable storage key, e.g. "7x8".
    var key: String { "\(a)x\(b)" }

    /// Uses U+00D7, never a lowercase letter x.
    var display: String { "\(a) \u{00D7} \(b)" }

    /// The fully revealed fact, shown after a wrong answer in Revision.
    var revealed: String { "\(display) = \(answer)" }
}
