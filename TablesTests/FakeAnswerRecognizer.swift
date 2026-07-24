import Foundation
@testable import Tables

@MainActor
final class FakeAnswerRecognizer: AnswerRecognizing {
    var onNumber: ((Int) -> Void)?

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

    /// Simulate the recogniser hearing a number. No-op unless listening,
    /// mirroring the real recogniser which only emits between start/stop.
    func emit(_ number: Int) {
        guard isListening else { return }
        onNumber?(number)
    }
}
