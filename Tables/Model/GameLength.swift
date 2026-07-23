import Foundation

enum GameLength: Hashable, Codable, Sendable {
    case seconds(Int)
    case questions(Int)
    case endless

    static let countdownOptions: [GameLength] = [
        .seconds(30), .seconds(60), .seconds(90), .seconds(120)
    ]

    static let revisionOptions: [GameLength] = [
        .questions(10), .questions(20), .questions(30),
        .questions(40), .questions(50), .questions(60), .endless
    ]

    /// Stable component of the score-board config key.
    var key: String {
        switch self {
        case .seconds(let value): "cd\(value)"
        case .questions(let value): "rev\(value)"
        case .endless: "revEndless"
        }
    }

    /// Full sentence for the setup screen's collapsed summary.
    var summary: String {
        switch self {
        case .seconds(let value): "\(value) seconds"
        case .questions(let value): "\(value) questions"
        case .endless: "Endless"
        }
    }

    /// Short form for the chip itself.
    var chipLabel: String {
        switch self {
        case .seconds(let value): "\(value)s"
        case .questions(let value): "\(value)"
        case .endless: "Endless"
        }
    }

    /// Compact form for the results eyebrow.
    var shortSummary: String {
        switch self {
        case .seconds(let value): "\(value) sec"
        case .questions(let value): "\(value) questions"
        case .endless: "endless"
        }
    }
}
