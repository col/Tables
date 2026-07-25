import Foundation

/// How eagerly voice recognition submits an answer, chosen on the settings
/// slider. Each notch sets the two settle durations the voice controller uses.
///
/// `Int`-backed so it maps directly onto a 5-step slider and persists as a small
/// integer. `nonisolated`: a pure Sendable value type (see `SpokenNumber`).
nonisolated enum VoiceSpeed: Int, CaseIterable, Codable, Sendable {
    case fastest, fast, normal, slow, slowest

    var label: String {
        switch self {
        case .fastest: "Fastest"
        case .fast: "Fast"
        case .normal: "Normal"
        case .slow: "Slow"
        case .slowest: "Slowest"
        }
    }

    /// Wait for a match or an off-track number — already decided, this is just a
    /// short insurance window in case it grows into a different number.
    var shortWait: Duration {
        switch self {
        case .fastest: .milliseconds(200)
        case .fast: .milliseconds(300)
        case .normal: .milliseconds(400)
        case .slow: .milliseconds(500)
        case .slowest: .milliseconds(600)
        }
    }

    /// Wait while on track toward the answer — longer patience to let the child
    /// finish saying it.
    var onTrackWait: Duration {
        switch self {
        case .fastest: .milliseconds(600)
        case .fast: .milliseconds(700)
        case .normal: .milliseconds(800)
        case .slow: .milliseconds(900)
        case .slowest: .milliseconds(1000)
        }
    }
}
