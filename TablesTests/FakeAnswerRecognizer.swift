import Foundation
@testable import Tables

@MainActor
final class FakeAnswerRecognizer: AnswerRecognizing {
    var onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)?

    var authorized = true
    private(set) var isListening = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        completion(authorized)
    }

    func start() {
        startCount += 1
        isListening = true
    }

    func stop() {
        if isListening { stopCount += 1 }
        isListening = false
    }

    /// Simulate a recognition partial. No-op unless listening, mirroring the
    /// real recogniser which only emits between start/stop.
    func emitPartial(_ number: Int?, isFinal: Bool) {
        guard isListening else { return }
        onPartial?(number, isFinal)
    }
}
