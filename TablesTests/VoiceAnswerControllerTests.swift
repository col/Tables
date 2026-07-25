import Testing
import Foundation
@testable import Tables

@MainActor
struct VoiceAnswerControllerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func make(speed: VoiceSpeed = .normal)
        -> (VoiceAnswerController, GameSession, FakeAnswerRecognizer, ManualSettleScheduler) {
        let config = GameConfig(mode: .countdown, tables: [3, 7], answerMode: .voice, length: .seconds(60))
        let session = GameSession(
            config: config,
            store: InMemoryProgressStore(),
            optionCount: 6,
            feedback: SilentFeedbackPlayer(),
            rng: SeededRandom(seed: 17)
        )
        session.start(now: start)
        let fake = FakeAnswerRecognizer()
        let scheduler = ManualSettleScheduler()
        let controller = VoiceAnswerController(
            session: session, recognizer: fake, scheduler: scheduler, speed: speed, now: { self.start }
        )
        return (controller, session, fake, scheduler)
    }

    @Test("syncToPhase starts listening while asking")
    func startsOnAsking() {
        let (controller, session, fake, _) = make()
        #expect(session.phase == .asking)
        controller.syncToPhase()
        #expect(fake.isListening)
        #expect(controller.display == .listening)
    }

    @Test("a terminal number submits immediately with no wait")
    func terminalSubmitsImmediately() {
        let (controller, _, fake, scheduler) = make()
        controller.syncToPhase()
        fake.emitPartial(7, isFinal: false)          // 7 is not extendable
        #expect(controller.display == .heard(7))
        #expect(fake.isListening == false)           // stopped on submit
        #expect(scheduler.lastDelay == nil)          // never scheduled a wait
        #expect(controller.progress == nil)
    }

    @Test("an extendable partial publishes progress and waits, choosing the delay by status")
    func extendableWaitsAndPublishes() {
        let (controller, session, fake, scheduler) = make()
        controller.syncToPhase()
        let answer = session.fact.answer
        // 20 is always extendable and never a ×3/×7 answer, so it isn't a match.
        fake.emitPartial(20, isFinal: false)
        let status = SpokenNumber.track(heard: 20, answer: answer)
        #expect(controller.progress == VoiceProgress(heard: 20, status: status))
        #expect(fake.isListening)                    // NOT submitted yet
        #expect(controller.display == .listening)
        let expected: Duration = status == .onTrack ? .milliseconds(800) : .milliseconds(400)
        #expect(scheduler.lastDelay == expected)
    }

    @Test("the injected speed sets the settle durations")
    func speedDrivesDurations() {
        let (controller, session, fake, scheduler) = make(speed: .fastest)
        controller.syncToPhase()
        let answer = session.fact.answer
        fake.emitPartial(20, isFinal: false)             // extendable, not a ×3/×7 answer
        let status = SpokenNumber.track(heard: 20, answer: answer)
        // Fastest = 200 short / 600 on-track — proves the speed flowed through.
        let expected: Duration = status == .onTrack ? .milliseconds(600) : .milliseconds(200)
        #expect(scheduler.lastDelay == expected)
    }

    @Test("a matching answer never waits the long on-track duration")
    func matchUsesShortWait() {
        let (controller, session, fake, scheduler) = make()
        controller.syncToPhase()
        let answer = session.fact.answer
        fake.emitPartial(answer, isFinal: false)     // heard == answer -> .matches
        if SpokenNumber.isExtendable(answer) {
            // Extendable match (e.g. answer 30, heard "thirty"): short insurance
            // wait, NOT the long on-track wait — we already have the answer.
            #expect(scheduler.lastDelay == .milliseconds(400))
            #expect(fake.isListening)                // waiting, not yet submitted
            #expect(controller.progress == VoiceProgress(heard: answer, status: .matches))
        } else {
            // Terminal match (the common case): submits immediately, no wait.
            #expect(controller.display == .heard(answer))
            #expect(scheduler.lastDelay == nil)
        }
    }

    @Test("firing the settle timer submits the pending number")
    func settleFiresSubmits() {
        let (controller, _, fake, scheduler) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)
        #expect(fake.isListening)                    // waiting
        scheduler.fire()
        #expect(controller.display == .heard(20))
        #expect(fake.isListening == false)
        #expect(controller.progress == nil)
    }

    @Test("a later terminal partial cancels the wait and submits the grown number")
    func laterTerminalCancelsWait() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)         // "twenty" — waiting
        fake.emitPartial(23, isFinal: false)         // "twenty three" — terminal
        #expect(controller.display == .heard(23))
        #expect(controller.progress == nil)
    }

    @Test("isFinal submits immediately")
    func isFinalSubmits() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: true)          // final transcript
        #expect(controller.display == .heard(20))
    }

    @Test("a late partial after submitting is ignored")
    func hasSubmittedBlocksLatePartial() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(7, isFinal: false)          // submits 7 -> phase leaves .asking
        fake.emitPartial(9, isFinal: false)          // ignored
        #expect(controller.display == .heard(7))
    }

    @Test("progress clears when the question leaves asking")
    func progressClearsOffAsking() {
        let (controller, session, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)
        #expect(controller.progress != nil)
        // Leave .asking without going through the controller's submit.
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)
        controller.syncToPhase()
        #expect(controller.progress == nil)
        #expect(controller.display == .idle)
    }

    @Test("a partial heard when not asking is ignored")
    func ignoresWhenNotAsking() {
        let (controller, session, fake, _) = make()
        controller.syncToPhase()
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)            // -> feedback
        controller.syncToPhase()                     // -> stop
        fake.emitPartial(99, isFinal: false)         // fake ignores (not listening)
        #expect(session.answered == 0)
    }
}
