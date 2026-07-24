import Foundation
import Speech
import AVFoundation

/// On-device speech recognition, scoped to hearing a single answer number.
///
/// Forces `requiresOnDeviceRecognition` so nothing leaves the phone. Each
/// `start()` opens a fresh recognition request; the first partial transcript
/// that `SpokenNumberParser` resolves to a valid number fires `onNumber` once
/// and then the recogniser stops itself.
///
/// Robustness note: several things can end a recognition task *without* a
/// number while the question is still being asked — a run of silence
/// (finalises the task), or an audio-session interruption (a call, Siri, an
/// alarm). Both are recovered here so an always-listening question never
/// silently goes deaf: a clean finalise restarts the task, and an interruption
/// is picked back up when it ends. These recovery paths depend on how the real
/// on-device recogniser behaves and should be confirmed on-device (Task 8).
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

    /// A recognised number that might still be growing ("twenty" → "twenty
    /// one"), held until the stream settles rather than fired on the first
    /// partial. Cleared once it fires or the recogniser stops.
    private var pendingNumber: Int?
    private var settleTask: Task<Void, Never>?
    /// How long a still-growing number must go without a newer partial before it
    /// submits — long enough to bridge the gap between the words of a compound
    /// number, short enough to stay responsive. Tuned by ear on device.
    private static let settleInterval: Duration = .milliseconds(400)

    /// Set on an interruption's `.began` so we know whether to resume on `.ended`.
    private var wasListeningBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// Registered lazily on first `start()` rather than in `init` (capturing
    /// `self` in an escaping closure during `init` is a Swift 6 concurrency
    /// error). The Sendable primitives are extracted on the delivery queue and
    /// then hopped to the main actor, so the non-Sendable Notification never
    /// crosses the boundary.
    private func registerInterruptionObserverIfNeeded() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let shouldResume = (info?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            Task { @MainActor [weak self] in self?.handleInterruption(type: type, shouldResume: shouldResume) }
        }
    }

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
        registerInterruptionObserverIfNeeded()
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
                // Errors (including audio-session interruptions) end the task.
                // Checked first, before any result handling, so a result+error
                // callback can't reach the restart path: interruptions are
                // recovered by the interruption observer; other errors just
                // stop. We deliberately do NOT auto-restart on error, to avoid
                // a tight failure loop.
                if error != nil {
                    self.stop()
                    return
                }
                guard let result else { return }
                let number = SpokenNumberParser.parse(result.bestTranscription.formattedString)
                if result.isFinal {
                    // The transcript is settled: submit the number now, or — if
                    // nothing parseable was heard (a run of silence) — restart so
                    // the question keeps listening rather than going deaf.
                    self.cancelSettle()
                    if let number {
                        self.fire(number)
                    } else {
                        self.restartListening()
                    }
                } else if let number, !self.isExtendable(number) {
                    // A number that can't grow by saying more ("forty two",
                    // "seven") — submit immediately.
                    self.cancelSettle()
                    self.fire(number)
                } else {
                    // Either an extendable number ("twenty", which may still
                    // become "twenty one") or any partial while one is pending:
                    // hold it and wait for the stream to go quiet, so a compound
                    // number isn't clipped to its prefix.
                    if let number { self.pendingNumber = number }
                    if self.pendingNumber != nil { self.armSettleTimer() }
                }
            }
        }
    }

    func stop() {
        // Any stop cancels a pending interruption-resume: if the question has
        // moved on (phase change, an answer) before an interruption's `.ended`
        // arrives, we must not later restart on a stale intent. Cleared BEFORE
        // the `isRunning` guard, because during an interruption window the
        // recogniser is already stopped (`.began` stopped it), so a phase-change
        // stop() arrives with `isRunning == false` and must still clear the flag.
        wasListeningBeforeInterruption = false
        cancelSettle()
        guard isRunning else { return }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil

        // Hand the shared audio session back so voice cleans up after itself:
        // restore the app's default `.ambient` (stop ducking others / holding
        // the record indicator) and deactivate. The next `start()` re-asserts
        // `.playAndRecord`, and FeedbackPlayer reactivates for its next tone —
        // so we don't rely on an unrelated component to undo our category.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Tear the current task down and immediately open a fresh one. Used when a
    /// task finalises with no answer but the question is still live.
    private func restartListening() {
        guard isRunning else { return }
        stop()
        start()
    }

    private func handleInterruption(type: AVAudioSession.InterruptionType?, shouldResume: Bool) {
        switch type {
        case .began:
            // The system has already suspended our audio. Capture the intent
            // *before* stop() clears it, then restore it so `.ended` knows to
            // resume — but a later non-interruption stop() (phase change, an
            // answer) will clear it again and correctly cancel the resume.
            let wasListening = isRunning
            stop()
            wasListeningBeforeInterruption = wasListening
        case .ended:
            let shouldRestart = wasListeningBeforeInterruption && shouldResume
            wasListeningBeforeInterruption = false
            if shouldRestart { start() }
        default:
            break
        }
    }

    /// Whether a recognised number might still grow if the child keeps speaking:
    /// the tens ("twenty" → "twenty one"), "one" (→ "one hundred …"), and any
    /// hundred (over-inclusive on purpose — a brief wait on 100–144 costs only a
    /// beat, whereas firing early would clip "one hundred forty four" to a
    /// prefix). Everything else in 1…144 is terminal and can submit at once.
    private func isExtendable(_ number: Int) -> Bool {
        number == 1 || (number >= 20 && number <= 90 && number % 10 == 0) || number >= 100
    }

    /// (Re)start the settle timer for `pendingNumber`. Every fresh partial resets
    /// it, so the number only submits once the stream has been quiet for
    /// `settleInterval` — i.e. the child has finished speaking it.
    private func armSettleTimer() {
        let generation = self.generation
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleInterval)
            guard !Task.isCancelled, let self, self.generation == generation,
                  let pending = self.pendingNumber else { return }
            self.cancelSettle()
            self.fire(pending)
        }
    }

    private func cancelSettle() {
        settleTask?.cancel()
        settleTask = nil
        pendingNumber = nil
    }

    private func fire(_ number: Int) {
        guard isRunning, !didFire else { return }
        didFire = true
        onNumber?(number)
        stop()
    }
}
