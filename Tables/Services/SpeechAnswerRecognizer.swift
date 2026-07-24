import Foundation
import Speech
import AVFoundation

/// On-device speech recognition, scoped to hearing a single answer number.
///
/// Forces `requiresOnDeviceRecognition` so nothing leaves the phone. Each
/// `start()` opens a fresh recognition request; the first partial transcript
/// that `SpokenNumberParser` resolves to a valid number fires `onNumber` once
/// and then the recogniser stops itself.
@MainActor
final class SpeechAnswerRecognizer: AnswerRecognizing {

    var onNumber: ((Int) -> Void)?

    /// Whether this device can offer voice mode at all (shown-in-setup gate).
    static var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false
    private var didFire = false

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                Task { @MainActor in completion(false) }
                return
            }
            AVAudioApplication.requestRecordPermission { micGranted in
                Task { @MainActor in completion(micGranted) }
            }
        }
    }

    func start() {
        guard !isRunning, let recognizer, recognizer.isAvailable else { return }
        isRunning = true
        didFire = false

        // Re-assert the record category on every start so it wins over
        // FeedbackPlayer's `.ambient`. `.duckOthers` lets our tones through.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result, let number = SpokenNumberParser.parse(result.bestTranscription.formattedString) {
                    self.fire(number)
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func fire(_ number: Int) {
        guard isRunning, !didFire else { return }
        didFire = true
        onNumber?(number)
        stop()
    }
}
