import Foundation

/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated enum AnswerMode: String, CaseIterable, Codable, Sendable {
    case multipleChoice
    case numberPad
    case voice

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .numberPad: "Number pad"
        case .voice: "Voice"
        }
    }

    var subtitle: String {
        switch self {
        case .multipleChoice: "Pick from the tiles"
        case .numberPad: "Type the answer"
        case .voice: "Say the answer"
        }
    }
}
