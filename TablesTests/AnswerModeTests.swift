import Testing
@testable import Tables

struct AnswerModeTests {
    @Test("voice case exists with copy")
    func voice() {
        #expect(AnswerMode.voice.rawValue == "voice")
        #expect(AnswerMode.voice.title == "Voice")
        #expect(AnswerMode.voice.subtitle == "Say the answer")
        #expect(AnswerMode.allCases.contains(.voice))
    }
}
