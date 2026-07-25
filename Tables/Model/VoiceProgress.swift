import Foundation

/// A snapshot of what the voice recogniser has heard so far, published for the
/// UI while a still-growing number is settling.
///
/// `nonisolated`: a pure Sendable value type shouldn't be main-actor-isolated
/// just because the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION`.
nonisolated struct VoiceProgress: Equatable, Sendable {
    /// Whether the heard number can still become the expected answer.
    enum Status: Equatable, Sendable {
        case matches    // heard == the expected answer
        case onTrack    // heard != answer but could still become it
        case offTrack   // cannot become the answer
    }

    let heard: Int
    let status: Status
}
