import Foundation

/// A source of recognised answer numbers. Abstracted so the game can run
/// against a fake (previews, tests) with no microphone.
@MainActor
protocol AnswerRecognizing: AnyObject {
    /// Fires once per recognised number while listening.
    var onNumber: ((Int) -> Void)? { get set }

    /// Request microphone + speech authorization. `granted` is true only when
    /// both are available. Safe to call repeatedly.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)

    /// Begin listening. Idempotent while already listening.
    func start()

    /// Stop listening and release the audio buffer.
    func stop()
}
