import Foundation

nonisolated struct RunRecord: Hashable, Sendable, Identifiable {
    let score: Int
    let answered: Int
    let date: Date

    var id: Date { date }
}

nonisolated struct ScoreBoardResult: Sendable {
    let topRuns: [RunRecord]
    let isNewBest: Bool
    /// nil when this is the first run for the configuration.
    let previousBest: Int?
    let bannerText: String
    /// The run just played. The results screen highlights this row, and
    /// identity by value is safer than guessing "the newest date".
    let current: RunRecord
}

/// Best runs are scoped to an exact configuration, so only like-for-like runs
/// are ever compared.
nonisolated enum ScoreBoard {
    static let maximumListed = 5

    static func evaluate(previousRuns: [RunRecord], current: RunRecord) -> ScoreBoardResult {
        let previousBest = previousRuns.map(\.score).max()
        let isNewBest = if let previousBest {
            current.score > previousBest
        } else {
            current.score > 0
        }

        let topRuns = (previousRuns + [current])
            .sorted { left, right in
                left.score == right.score ? left.date < right.date : left.score > right.score
            }
            .prefix(maximumListed)

        return ScoreBoardResult(
            topRuns: Array(topRuns),
            isNewBest: isNewBest,
            previousBest: previousBest,
            bannerText: bannerText(previousBest: previousBest, isNewBest: isNewBest),
            current: current
        )
    }

    private static func bannerText(previousBest: Int?, isNewBest: Bool) -> String {
        guard let previousBest else {
            return isNewBest ? "New personal best" : "Your first run \u{2014} every one counts"
        }
        return isNewBest
            ? "New personal best \u{2014} beat \(previousBest)"
            : "Your best is \(previousBest)"
    }

    static func relativeDateLabel(for date: Date, isCurrentRun: Bool, now: Date) -> String {
        if isCurrentRun { return "Just now" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "Earlier today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}
