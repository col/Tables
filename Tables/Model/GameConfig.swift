import Foundation

/// Everything the player chose on the setup screen. Scores are scoped to this
/// whole shape, so only like-for-like runs are ever compared.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated struct GameConfig: Hashable, Sendable {
    var mode: GameMode
    var tables: Set<Int>
    var answerMode: AnswerMode
    var length: GameLength

    static let allTables = Set(1...12)
    static let multiplicands = 1...12

    var sortedTables: [Int] { tables.sorted() }

    var configKey: String {
        let tableList = sortedTables.map(String.init).joined(separator: "-")
        return "\(mode.rawValue)|\(tableList)|\(answerMode.rawValue)|\(length.key)"
    }

    var facts: [Fact] {
        sortedTables.flatMap { a in
            Self.multiplicands.map { Fact(a: a, b: $0) }
        }
    }

    var isStartable: Bool { !tables.isEmpty }

    var tablesSummary: String {
        if tables.isEmpty { return "None chosen" }
        if tables == Self.allTables { return "All tables" }
        return sortedTables.map { "\u{00D7}\($0)" }.joined(separator: "  ")
    }

    /// Single-space variant used in the results eyebrow.
    var compactTablesSummary: String {
        if tables.isEmpty { return "none chosen" }
        if tables == Self.allTables { return "all tables" }
        return sortedTables.map { "\u{00D7}\($0)" }.joined(separator: " ")
    }

    /// e.g. "Countdown · 60 sec · ×3 ×6 ×7 ×8"
    var summary: String {
        "\(mode.title) \u{00B7} \(length.shortSummary) \u{00B7} \(compactTablesSummary)"
    }

    static let `default` = GameConfig(
        mode: .countdown,
        tables: [3, 6, 7, 8],
        answerMode: .multipleChoice,
        length: .seconds(60)
    )
}
