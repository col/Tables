import Testing
import Foundation
@testable import Tables

@MainActor
struct VoiceAnswerControllerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func make() -> (VoiceAnswerController, GameSession, FakeAnswerRecognizer) {
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
        let controller = VoiceAnswerController(session: session, recognizer: fake, now: { self.start })
        return (controller, session, fake)
    }

    @Test("syncToPhase starts listening while asking")
    func startsOnAsking() {
        let (controller, session, fake) = make()
        #expect(session.phase == .asking)
        controller.syncToPhase()
        #expect(fake.isListening)
        #expect(controller.display == .listening)
    }

    @Test("a heard number submits through the session")
    func submits() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        let answer = session.fact.answer
        fake.emit(answer)
        // Correct answer in countdown scores and enters feedback.
        #expect(session.score == 1)
        #expect(fake.isListening == false)          // stopped after a hit
        if case .heard(let n) = controller.display { #expect(n == answer) } else { Issue.record("expected .heard") }
    }

    @Test("stops listening when the question is not asking")
    func stopsOffAsking() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        #expect(fake.isListening)
        // Submit a wrong answer to leave .asking (countdown feedback hold).
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)
        controller.syncToPhase()
        #expect(fake.isListening == false)
        #expect(controller.display == .idle)
    }

    @Test("a number heard when not asking is ignored")
    func ignoresWhenNotAsking() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)   // -> feedback
        controller.syncToPhase()            // -> stop
        fake.emit(99)                       // fake ignores because not listening
        #expect(session.answered == 0)
    }
}
