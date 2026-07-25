import Foundation
import Observation

/// Bridges a `GameSession` to an `AnswerRecognizing` source, owning the
/// answer-aware settle timing.
///
/// It listens only while the question is `.asking`. A number that can't grow
/// (terminal) submits at once; a still-growing number is held for a settle
/// window whose length depends on whether it could still become the correct
/// answer — longer when on track, short when off track. All audio lives in the
/// recogniser; this controller is pure enough to test with a fake recogniser, a
/// seeded session, and a manual scheduler.
@MainActor
@Observable
final class VoiceAnswerController {

    enum Display: Equatable {
        case idle
        case listening
        case heard(Int)
    }

    private(set) var display: Display = .idle
    /// The latest heard number + on-track status while a number is settling;
    /// `nil` when nothing is mid-recognition. Published for the UI.
    private(set) var progress: VoiceProgress?

    private let session: GameSession
    private let recognizer: any AnswerRecognizing
    private let scheduler: any SettleScheduling
    private let now: () -> Date

    private var pendingNumber: Int?
    private var hasSubmitted = false

    /// Long patience — only when the child is on track toward the answer but
    /// hasn't said it yet, so give them time to finish it.
    private static let onTrackWait: Duration = .milliseconds(1200)
    /// Short insurance — a match (we already have the correct answer, but it
    /// could still grow into a wrong one, e.g. "thirty" → "thirty two") or an
    /// off-track number (already wrong, just capturing the whole of it).
    private static let shortWait: Duration = .milliseconds(400)

    init(session: GameSession,
         recognizer: any AnswerRecognizing,
         scheduler: (any SettleScheduling)? = nil,
         now: @escaping () -> Date = { Date() }) {
        self.session = session
        self.recognizer = recognizer
        // Defaulted via `nil` rather than `= TaskSettleScheduler()` directly:
        // the synthesized default-argument expression runs in a nonisolated
        // context and can't call a @MainActor-isolated initializer (same
        // constraint as `SpeechAnswerRecognizer.isSupported`'s doc comment).
        // Constructing it here in the init body is fine — `self` is already
        // on MainActor by the time this runs.
        self.scheduler = scheduler ?? TaskSettleScheduler()
        self.now = now
        self.recognizer.onPartial = { [weak self] number, isFinal in
            self?.considerPartial(number: number, isFinal: isFinal)
        }
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        recognizer.requestAuthorization(completion)
    }

    /// Call on appear and whenever `session.phase` changes.
    func syncToPhase() {
        if session.phase == .asking {
            if display != .listening {
                resetForNewQuestion()
                display = .listening
                recognizer.start()
            }
        } else {
            stop()
        }
    }

    /// Release the recogniser when the view goes away or the child opts out of
    /// voice — no phase change fires on view teardown.
    func stopListening() {
        stop()
    }

    private func considerPartial(number: Int?, isFinal: Bool) {
        guard session.phase == .asking, !hasSubmitted else { return }

        if isFinal {
            if let number { submit(number) }        // else: recogniser restarts itself
            return
        }

        if let number, !SpokenNumber.isExtendable(number) {
            submit(number)                          // terminal = complete answer
            return
        }

        if let number { pendingNumber = number }    // extendable candidate

        guard let pending = pendingNumber else { return }
        let status = SpokenNumber.track(heard: pending, answer: session.fact.answer)
        progress = VoiceProgress(heard: pending, status: status)
        // Only a genuinely on-track number earns the long wait; a match already
        // has the right answer and just needs the short insurance window.
        let wait = status == .onTrack ? Self.onTrackWait : Self.shortWait
        VoiceLog.log("heard \(pending) \(status) wait=\(wait)")
        scheduler.schedule(after: wait) { [weak self] in
            self?.settleFired()
        }
    }

    private func settleFired() {
        guard session.phase == .asking, !hasSubmitted, let pending = pendingNumber else { return }
        submit(pending)
    }

    private func submit(_ number: Int) {
        VoiceLog.log("submit \(number)")
        hasSubmitted = true
        pendingNumber = nil
        progress = nil
        scheduler.cancel()
        display = .heard(number)
        recognizer.stop()
        session.submit(number, now: now())
    }

    private func resetForNewQuestion() {
        hasSubmitted = false
        pendingNumber = nil
        progress = nil
        scheduler.cancel()
    }

    private func stop() {
        scheduler.cancel()
        pendingNumber = nil
        progress = nil
        guard display != .idle else { return }
        display = .idle
        recognizer.stop()
    }
}
