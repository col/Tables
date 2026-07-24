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
    /// `nonisolated` so it can be used as a default-argument expression (default
    /// arguments in this project's Swift 5 language mode can't reference
    /// actor-isolated members) — the check itself touches no isolated state.
    nonisolated static var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false
    private var didFire = false
    /// Bumped on every `start()`. A recognition task's completion handler can
    /// still fire after `cancel()` (cancellation is not synchronous), so each
    /// callback captures the generation it was started under and ignores itself
    /// if a later `start()` has since superseded it — otherwise a stale task
    /// from the previous question could kill or answer the current one.
    private var generation = 0

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
        generation += 1
        let generation = self.generation

        // Re-assert the record category on every start so it wins over
        // FeedbackPlayer's `.ambient`. `.duckOthers` lets our tones through.
        // `try?`: on the rare failure (session held exclusively elsewhere) we
        // let `engine.start()` below throw and drive cleanup, rather than
        // aborting before the engine is even attempted.
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
                // Ignore a callback from a task that a later start() superseded.
                guard generation == self.generation else { return }
                if let result, let number = SpokenNumberParser.parse(result.bestTranscription.formattedString) {
                    self.fire(number)
                } else if error != nil {
                    self.stop()
                }
                // Note: a clean final result with no parseable number leaves the
                // engine running (still listening) until the controller calls
                // stop() on a phase change. Verify on-device (Task 8) that an
                // on-device task ending mid-question restarts listening as
                // expected; adjust here if real behaviour differs.
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
