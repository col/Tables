import Foundation

/// A source of recognised answer numbers. Abstracted so the game can run
/// against a fake (previews, tests) with no microphone.
@MainActor
protocol AnswerRecognizing: AnyObject {
    /// Fires for each recognition update while listening: the parsed number so
    /// far (`nil` if the transcript isn't yet a number) and whether the
    /// transcript is final. The consumer decides when to submit.
    var onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)? { get set }

    /// Request microphone + speech authorization. `granted` is true only when
    /// both are available. Safe to call repeatedly.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)

    /// Begin listening. Idempotent while already listening.
    func start()

    /// Stop listening and release the audio buffer.
    func stop()
}
