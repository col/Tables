import Foundation
import Observation

/// Bridges a `GameSession` to an `AnswerRecognizing` source.
///
/// It listens only while the question is `.asking`, submits the first number it
/// hears through the same `submit(_:now:)` seam the number pad uses, and stops
/// during feedback holds. All audio lives in the recogniser; this controller is
/// pure enough to test with a fake and a seeded session.
@MainActor
@Observable
final class VoiceAnswerController {

    enum Display: Equatable {
        case idle
        case listening
        case heard(Int)
    }

    private(set) var display: Display = .idle

    private let session: GameSession
    private let recognizer: any AnswerRecognizing
    private let now: () -> Date

    init(session: GameSession, recognizer: any AnswerRecognizing, now: @escaping () -> Date = { Date() }) {
        self.session = session
        self.recognizer = recognizer
        self.now = now
        self.recognizer.onNumber = { [weak self] number in
            self?.handle(number)
        }
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        recognizer.requestAuthorization(completion)
    }

    /// Call on appear and whenever `session.phase` changes.
    func syncToPhase() {
        if session.phase == .asking {
            if display != .listening {
                display = .listening
                recognizer.start()
            }
        } else {
            stop()
        }
    }

    private func handle(_ number: Int) {
        guard session.phase == .asking else { return }
        display = .heard(number)
        recognizer.stop()
        session.submit(number, now: now())
    }

    private func stop() {
        guard display != .idle else { return }
        display = .idle
        recognizer.stop()
    }
}
