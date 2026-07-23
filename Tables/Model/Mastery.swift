import Foundation

/// A plain snapshot of one fact's answering history, free of SwiftData so the
/// rules below can be tested as values.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated struct FactHistory: Hashable, Sendable {
    var attempts: Int
    var correctCount: Int
    var averageMillis: Double

    static let unseen = FactHistory(attempts: 0, correctCount: 0, averageMillis: 0)

    var isUnseen: Bool { attempts == 0 }
}

/// The three display states a fact can be in: not yet attempted, improving, or fully mastered.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum MasteryLevel: Hashable, Sendable, CaseIterable {
    case notYet
    case gettingThere
    case mastered

    var legendLabel: String {
        switch self {
        case .notYet: "Not yet"
        case .gettingThere: "Getting there"
        case .mastered: "Mastered"
        }
    }
}

/// Rules for determining and updating mastery of a times-tables fact.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum Mastery {
    /// One lucky fast answer should not read as mastery.
    static let requiredCorrectCount = 3
    static let masteryThresholdMillis: Double = 3000

    /// Exponential moving average, so the figure tracks current ability rather
    /// than staying anchored by early fumbling.
    static let emaAlpha = 0.3

    static func level(for history: FactHistory) -> MasteryLevel {
        guard history.attempts > 0 else { return .notYet }
        if history.correctCount >= requiredCorrectCount
            && history.averageMillis < masteryThresholdMillis {
            return .mastered
        }
        return .gettingThere
    }

    /// `correctCount` is the count *before* this answer is folded in.
    static func updatedAverage(
        current: Double,
        correctCount: Int,
        latestMillis: Double
    ) -> Double {
        guard correctCount > 0 else { return latestMillis }
        return emaAlpha * latestMillis + (1 - emaAlpha) * current
    }
}
