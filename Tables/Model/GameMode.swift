import Foundation

/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum GameMode: String, CaseIterable, Codable, Sendable {
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
