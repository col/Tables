import Testing
import Foundation
@testable import Tables

@MainActor
struct GameSessionTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSession(
        mode: GameMode = .countdown,
        length: GameLength = .seconds(60),
        answerMode: AnswerMode = .multipleChoice,
        tables: Set<Int> = [3, 7],
        store: (any ProgressRecording)? = nil
    ) -> (GameSession, any ProgressRecording) {
        let backing = store ?? InMemoryProgressStore()
        let config = GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
        let session = GameSession(
            config: config,
            store: backing,
            optionCount: 6,
            feedback: SilentFeedbackPlayer(),
            rng: SeededRandom(seed: 17)
        )
        return (session, backing)
    }

    /// Advances the session to `date` in small steps, as the real timer does.
    private func run(_ session: GameSession, from: Date, to: Date) {
        var now = from
        while now < to {
            now = min(to, now.addingTimeInterval(0.05))
            session.tick(now: now)
        }
    }

    // MARK: Countdown

    @Test("a correct answer scores and moves on")
    func countdownCorrectScores() {
        let (session, _) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer, now: start.addingTimeInterval(1))
        #expect(session.score == 1)
        #expect(session.answered == 1)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(isCorrect)
            #expect(!text.isEmpty)
        } else {
            Issue.record("expected feedback phase, got \(session.phase)")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(3))
        #expect(session.phase == .asking)
        #expect(session.fact != first)
    }

    @Test("a wrong answer keeps the same question and costs no point")
    func countdownWrongRetries() {
        let (session, _) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 1, now: start.addingTimeInterval(1))
        #expect(session.score == 0)
        #expect(session.answered == 0)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(!isCorrect)
            #expect(text == "Not quite \u{2014} try again")
        } else {
            Issue.record("expected feedback phase, got \(session.phase)")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(3))
        #expect(session.phase == .asking)
        #expect(session.fact == first, "the question changed after a wrong answer")
        #expect(session.pickedValue == nil)
        #expect(session.padValue.isEmpty)
    }

    @Test("a retry after a wrong answer scores but records no timing")
    func countdownRetryRecordsNoTiming() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 1, now: start.addingTimeInterval(1))
        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(2))
        session.submit(first.answer, now: start.addingTimeInterval(3))

        #expect(session.score == 1)
        let history = store.history()[first.key]!
        #expect(history.attempts == 2)
        // correctCount in FactHistory counts *timed* correct answers only.
        #expect(history.correctCount == 0, "an untrustworthy retry was timed")
        #expect(history.averageMillis == 0)
    }

    @Test("a first-attempt correct answer is timed")
    func countdownFirstAttemptIsTimed() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer, now: start.addingTimeInterval(1.5))
        let history = store.history()[first.key]!
        #expect(history.correctCount == 1)
        #expect(abs(history.averageMillis - 1500) < 50)
    }

    @Test("the clock runs down and ends the game at zero")
    func countdownExpires() {
        let (session, store) = makeSession(length: .seconds(30))
        session.start(now: start)
        #expect(session.secondsRemaining == 30)

        run(session, from: start, to: start.addingTimeInterval(10))
        #expect(session.secondsRemaining == 20)
        #expect(session.phase != .finished)

        run(session, from: start.addingTimeInterval(10), to: start.addingTimeInterval(31))
        #expect(session.phase == .finished)
        #expect(session.secondsRemaining == 0)
        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("the clock reads as low in the final ten seconds")
    func lowTimeThreshold() {
        let (session, _) = makeSession(length: .seconds(30))
        session.start(now: start)
        #expect(!session.isLowTime)
        run(session, from: start, to: start.addingTimeInterval(20.5))
        #expect(session.isLowTime)
    }

    @Test("the timer text is minutes and seconds")
    func timerText() {
        let (session, _) = makeSession(length: .seconds(120))
        session.start(now: start)
        #expect(session.timeText == "2:00")
        run(session, from: start, to: start.addingTimeInterval(61))
        #expect(session.timeText == "0:59")
    }

    @Test("backgrounding pauses the clock rather than punishing an interruption")
    func pauseAndResume() {
        let (session, _) = makeSession(length: .seconds(60))
        session.start(now: start)
        run(session, from: start, to: start.addingTimeInterval(10))
        #expect(session.secondsRemaining == 50)

        session.pause(now: start.addingTimeInterval(10))
        // Thirty seconds elapse in the background.
        session.tick(now: start.addingTimeInterval(40))
        #expect(session.secondsRemaining == 50, "the clock ran while backgrounded")

        session.resume(now: start.addingTimeInterval(40))
        session.tick(now: start.addingTimeInterval(40))
        #expect(session.secondsRemaining == 50)
        run(session, from: start.addingTimeInterval(40), to: start.addingTimeInterval(45))
        #expect(session.secondsRemaining == 45)
    }

    @Test("a question interrupted by backgrounding is not timed as slow")
    func pauseDoesNotSkewFactTiming() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.pause(now: start.addingTimeInterval(1))
        session.resume(now: start.addingTimeInterval(300))
        session.submit(first.answer, now: start.addingTimeInterval(301))

        let history = store.history()[first.key]!
        #expect(history.averageMillis < 3000, "a background pause was counted as thinking time")
    }

    // MARK: Revision

    @Test("a wrong answer reveals the fact and moves on")
    func revisionRevealsAndAdvances() {
        let (session, _) = makeSession(mode: .revision, length: .questions(10))
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 3, now: start.addingTimeInterval(1))
        #expect(session.answered == 1)
        #expect(session.score == 0)
        #expect(session.revealAnswer)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(!isCorrect)
            #expect(text == first.revealed)
        } else {
            Issue.record("expected feedback phase")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(4))
        #expect(session.fact != first)
        #expect(session.phase == .asking)
    }

    @Test("a fixed-length session ends after exactly the chosen number of questions")
    func revisionFixedLengthTerminates() {
        let (session, store) = makeSession(mode: .revision, length: .questions(10))
        session.start(now: start)

        var now = start
        for index in 1...10 {
            now = now.addingTimeInterval(1)
            session.submit(session.fact.answer, now: now)
            #expect(session.answered == index)
            let next = now.addingTimeInterval(3)
            run(session, from: now, to: next)
            now = next
        }

        #expect(session.phase == .finished)
        #expect(session.answered == 10)
        #expect(session.score == 10)
        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("an endless session keeps going until the child finishes it")
    func endlessRunsOn() {
        let (session, _) = makeSession(mode: .revision, length: .endless)
        session.start(now: start)
        #expect(session.endLabel == "Finish")

        var now = start
        for _ in 1...25 {
            now = now.addingTimeInterval(1)
            session.submit(session.fact.answer, now: now)
            let next = now.addingTimeInterval(3)
            run(session, from: now, to: next)
            now = next
        }
        #expect(session.phase != .finished)
        #expect(session.answered == 25)

        #expect(session.endEarly(now: now) == .finished)
        #expect(session.phase == .finished)
    }

    @Test("the progress pill counts up, and shows a target when there is one")
    func revisionProgressText() {
        let (fixed, _) = makeSession(mode: .revision, length: .questions(20))
        fixed.start(now: start)
        #expect(fixed.revisionProgressText == "0/20")

        let (endless, _) = makeSession(mode: .revision, length: .endless)
        endless.start(now: start)
        #expect(endless.revisionProgressText == "0")
    }

    // MARK: Ending early

    @Test("quitting before answering anything records nothing")
    func abandoningRecordsNothing() {
        let (session, store) = makeSession()
        session.start(now: start)
        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .abandoned)
        #expect(store.runs(forConfigKey: session.config.configKey).isEmpty)
        #expect(session.phase != .finished)
    }

    @Test("quitting after answering records the run")
    func endingEarlyRecordsTheRun() {
        let (session, store) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))

        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)
        #expect(session.phase == .finished)
        let runs = store.runs(forConfigKey: session.config.configKey)
        #expect(runs.count == 1)
        #expect(runs[0].score == 1)
    }

    @Test("a second end tap does not record the run twice")
    func endingTwiceRecordsOneRun() {
        let (session, store) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))

        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)
        // A double-tap, or a race with the clock finishing on its own.
        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)

        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("the summary carries the score board")
    func summaryCarriesTheBoard() {
        let store = InMemoryProgressStore()
        let (first, _) = makeSession(store: store)
        first.start(now: start)
        first.submit(first.fact.answer, now: start.addingTimeInterval(1))
        _ = first.endEarly(now: start.addingTimeInterval(2))

        let (second, _) = makeSession(store: store)
        second.start(now: start.addingTimeInterval(100))
        second.submit(second.fact.answer, now: start.addingTimeInterval(101))
        // Advance past the feedback hold to the next question before answering
        // again — two submits at the same instant would be one scoring answer
        // plus one swallowed double-tap, leaving the second run tied with the
        // first rather than beating it.
        run(second, from: start.addingTimeInterval(101), to: start.addingTimeInterval(103))
        second.submit(second.fact.answer, now: start.addingTimeInterval(104))
        _ = second.endEarly(now: start.addingTimeInterval(120))

        let summary = try! #require(second.summary)
        #expect(second.score == 2)
        #expect(summary.board.previousBest == 1)
        #expect(summary.board.isNewBest)
    }

    // MARK: Number pad

    @Test("the pad builds a value, deletes, and caps at three digits")
    func padEditing() {
        let (session, _) = makeSession(answerMode: .numberPad)
        session.start(now: start)

        session.padAppend(4)
        session.padAppend(2)
        #expect(session.padValue == "42")
        #expect(session.canSubmitPad)

        session.padDelete()
        #expect(session.padValue == "4")

        session.padAppend(1)
        session.padAppend(2)
        session.padAppend(3)
        #expect(session.padValue == "412", "the pad should stop at three digits")
    }

    @Test("submitting an empty pad does nothing")
    func padWillNotSubmitEmpty() {
        let (session, _) = makeSession(answerMode: .numberPad)
        session.start(now: start)
        #expect(!session.canSubmitPad)
        session.padSubmit(now: start.addingTimeInterval(1))
        #expect(session.phase == .asking)
        #expect(session.answered == 0)
    }

    @Test("multiple choice offers the configured number of options, including the answer")
    func optionsMatchSettings() {
        let (session, _) = makeSession()
        session.start(now: start)
        #expect(session.options.count == 6)
        #expect(session.options.contains(session.fact.answer))
    }

    @Test("answers are ignored while feedback is showing")
    func inputIsIgnoredDuringFeedback() {
        let (session, _) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))
        session.submit(session.fact.answer, now: start.addingTimeInterval(1.1))
        #expect(session.score == 1, "a double tap scored twice")
    }
}
