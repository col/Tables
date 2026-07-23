import Foundation
import Observation

/// A concrete `RandomNumberGenerator` wrapping any other one.
///
/// Needed because Swift will not implicitly open an existential passed as
/// `inout`, and every random API in the standard library takes its generator
/// that way. Tests inject a seeded generator through this; the app injects
/// `SystemRandomNumberGenerator`.
///
/// `nonisolated`: see `GameLength` for why — a pure Sendable value type
/// should not be main-actor-isolated just because the app target defaults
/// to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
nonisolated struct AnyRandomGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}

/// Drives one game from first question to final score.
///
/// Nothing here reads the system clock. Every command takes `now`, and
/// `tick(now:)` advances holds, cross-fades and the countdown — so a full
/// two-minute game plays out in a unit test in microseconds, and pausing for a
/// backgrounded app is a matter of shifting deadlines rather than special
/// cases.
@MainActor
@Observable
final class GameSession {

    enum Phase: Equatable {
        case asking
        case feedback(isCorrect: Bool, text: String)
        case finished
    }

    enum EndOutcome: Equatable {
        case abandoned
        case finished
    }

    struct Summary {
        let config: GameConfig
        let score: Int
        let answered: Int
        let board: ScoreBoardResult
    }

    // Hold durations, carried over from the design prototype.
    private static let countdownCorrectHold: TimeInterval = 0.75
    private static let countdownWrongHold: TimeInterval = 0.85
    private static let revisionHold: TimeInterval = 1.30
    private static let fadeDuration: TimeInterval = 0.24
    static let lowTimeThreshold = 10

    private static let praise = [
        "Nice!", "Correct!", "Well done!", "Great!", "Yes!",
        "Spot on!", "Brilliant!", "Perfect!", "That's it!", "Lovely!"
    ]

    let config: GameConfig

    private(set) var fact: Fact
    private(set) var options: [Int] = []
    private(set) var padValue: String = ""
    private(set) var phase: Phase = .asking
    private(set) var score = 0
    private(set) var answered = 0
    private(set) var secondsRemaining = 0
    private(set) var pickedValue: Int?
    private(set) var revealAnswer = false
    private(set) var isFadingOut = false
    private(set) var summary: Summary?

    @ObservationIgnored private let store: any ProgressRecording
    @ObservationIgnored private let feedback: any FeedbackPlaying
    @ObservationIgnored private let picker: QuestionPicker
    @ObservationIgnored private let optionCount: Int
    @ObservationIgnored private var rng: AnyRandomGenerator

    @ObservationIgnored private var questionStartedAt: Date
    @ObservationIgnored private var firstAttemptWasWrong = false
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var fadeUntil: Date?
    @ObservationIgnored private var pausedAt: Date?

    init(
        config: GameConfig,
        store: any ProgressRecording,
        optionCount: Int,
        feedback: any FeedbackPlaying,
        rng: any RandomNumberGenerator
    ) {
        self.config = config
        self.store = store
        self.optionCount = optionCount
        self.feedback = feedback
        self.rng = AnyRandomGenerator(rng)
        self.picker = QuestionPicker(facts: config.facts, mode: config.mode)
        self.fact = config.facts.first ?? Fact(a: 1, b: 1)
        self.questionStartedAt = Date(timeIntervalSince1970: 0)
    }

    // MARK: Derived state

    var isLowTime: Bool {
        config.mode == .countdown && secondsRemaining <= Self.lowTimeThreshold
    }

    var timeText: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var revisionProgressText: String {
        if case .questions(let target) = config.length { return "\(answered)/\(target)" }
        return "\(answered)"
    }

    var endLabel: String {
        config.mode == .revision && config.length == .endless ? "Finish" : "End session"
    }

    var canSubmitPad: Bool { !padValue.isEmpty }

    var feedbackText: String {
        if case .feedback(_, let text) = phase { return text }
        return ""
    }

    // MARK: Commands

    func start(now: Date) {
        score = 0
        answered = 0
        summary = nil
        pausedAt = nil
        if case .seconds(let total) = config.length {
            deadline = now.addingTimeInterval(TimeInterval(total))
            secondsRemaining = total
        }
        nextQuestion(now: now)
    }

    func submit(_ value: Int, now: Date) {
        guard phase == .asking else { return }
        let isCorrect = value == fact.answer
        let millis = now.timeIntervalSince(questionStartedAt) * 1000
        pickedValue = value

        switch config.mode {
        case .countdown:
            if isCorrect {
                // A retry proves knowledge but not speed, so it goes untimed.
                store.recordCorrect(fact, millis: firstAttemptWasWrong ? nil : millis, at: now)
                score += 1
                answered += 1
                feedback.correct()
                phase = .feedback(isCorrect: true, text: Self.praise.randomElement(using: &rng)!)
                holdUntil = now.addingTimeInterval(Self.countdownCorrectHold)
            } else {
                store.recordIncorrect(fact, at: now)
                firstAttemptWasWrong = true
                feedback.incorrect()
                phase = .feedback(isCorrect: false, text: "Not quite \u{2014} try again")
                holdUntil = now.addingTimeInterval(Self.countdownWrongHold)
            }

        case .revision:
            answered += 1
            if isCorrect {
                store.recordCorrect(fact, millis: millis, at: now)
                score += 1
                feedback.correct()
                phase = .feedback(isCorrect: true, text: Self.praise.randomElement(using: &rng)!)
            } else {
                store.recordIncorrect(fact, at: now)
                revealAnswer = true
                feedback.incorrect()
                phase = .feedback(isCorrect: false, text: fact.revealed)
            }
            holdUntil = now.addingTimeInterval(Self.revisionHold)
        }
    }

    func padAppend(_ digit: Int) {
        guard phase == .asking, padValue.count < 3 else { return }
        padValue.append(String(digit))
    }

    func padDelete() {
        guard phase == .asking else { return }
        padValue = String(padValue.dropLast())
    }

    func padSubmit(now: Date) {
        guard let value = Int(padValue) else { return }
        submit(value, now: now)
    }

    func tick(now: Date) {
        guard phase != .finished, pausedAt == nil else { return }

        if let deadline {
            secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            if now >= deadline {
                finish(now: now)
                return
            }
        }

        if let fadeUntil, now >= fadeUntil {
            nextQuestion(now: now)
            return
        }

        if let hold = holdUntil, now >= hold {
            holdUntil = nil
            if config.mode == .countdown, case .feedback(false, _) = phase {
                // Retry the same question rather than moving on.
                phase = .asking
                pickedValue = nil
                padValue = ""
                return
            }
            if case .questions(let target) = config.length, answered >= target {
                finish(now: now)
                return
            }
            isFadingOut = true
            fadeUntil = now.addingTimeInterval(Self.fadeDuration)
        }
    }

    func endEarly(now: Date) -> EndOutcome {
        guard answered > 0 else { return .abandoned }
        finish(now: now)
        return .finished
    }

    /// The app went to the background. Deadlines resume where they left off.
    func pause(now: Date) {
        guard pausedAt == nil, phase != .finished else { return }
        pausedAt = now
    }

    func resume(now: Date) {
        guard let pausedAt else { return }
        let elapsed = now.timeIntervalSince(pausedAt)
        deadline = deadline?.addingTimeInterval(elapsed)
        holdUntil = holdUntil?.addingTimeInterval(elapsed)
        fadeUntil = fadeUntil?.addingTimeInterval(elapsed)
        questionStartedAt = questionStartedAt.addingTimeInterval(elapsed)
        self.pausedAt = nil
    }

    // MARK: Internals

    private func nextQuestion(now: Date) {
        // nil only on the very first question, when there is nothing to avoid.
        let previous = (answered > 0 || firstAttemptWasWrong) ? fact : nil
        fact = picker.next(history: store.history(), previous: previous, using: &rng)
        options = config.answerMode == .multipleChoice
            ? DistractorGenerator.options(for: fact, count: optionCount, using: &rng)
            : []
        padValue = ""
        pickedValue = nil
        revealAnswer = false
        isFadingOut = false
        firstAttemptWasWrong = false
        holdUntil = nil
        fadeUntil = nil
        questionStartedAt = now
        phase = .asking
    }

    private func finish(now: Date) {
        deadline = nil
        holdUntil = nil
        fadeUntil = nil
        isFadingOut = false
        secondsRemaining = 0

        let previousRuns = store.runs(forConfigKey: config.configKey)
        let current = RunRecord(score: score, answered: answered, date: now)
        store.recordRun(configKey: config.configKey, score: score, answered: answered, at: now)

        summary = Summary(
            config: config,
            score: score,
            answered: answered,
            board: ScoreBoard.evaluate(previousRuns: previousRuns, current: current)
        )
        phase = .finished
    }
}
