import Foundation

enum GameMode: String, CaseIterable, Codable, Sendable {
    case countdown
    case revision

    var title: String {
        switch self {
        case .countdown: "Countdown"
        case .revision: "Revision"
        }
    }

    var lowercasedTitle: String { title.lowercased() }

    /// The setup screen labels the third section differently per mode.
    var lengthSectionLabel: String {
        switch self {
        case .countdown: "Time limit"
        case .revision: "Length"
        }
    }
}
