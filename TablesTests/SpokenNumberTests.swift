import Testing
@testable import Tables

struct SpokenNumberTests {

    @Test("canonical words", arguments: [
        (3, ["three"]),
        (30, ["thirty"]),
        (36, ["thirty", "six"]),
        (7, ["seven"]),
        (20, ["twenty"]),
        (99, ["ninety", "nine"]),
        (100, ["one", "hundred"]),
        (105, ["one", "hundred", "five"]),
        (120, ["one", "hundred", "twenty"]),
        (144, ["one", "hundred", "forty", "four"]),
    ])
    func words(n: Int, expected: [String]) {
        #expect(SpokenNumber.words(n) == expected)
    }

    @Test("isExtendable", arguments: [
        (1, true), (20, true), (90, true), (100, true), (140, true),
        (7, false), (11, false), (36, false), (42, false), (99, false),
    ])
    func extendable(n: Int, expected: Bool) {
        #expect(SpokenNumber.isExtendable(n) == expected)
    }

    @Test("track vs answer 36", arguments: [
        (36, VoiceProgress.Status.matches),
        (30, .onTrack),
        (3, .offTrack),
        (40, .offTrack),
        (42, .offTrack),
        (20, .offTrack),
    ])
    func track36(heard: Int, expected: VoiceProgress.Status) {
        #expect(SpokenNumber.track(heard: heard, answer: 36) == expected)
    }

    @Test("track vs answer 144", arguments: [
        (144, VoiceProgress.Status.matches),
        (1, .onTrack),
        (100, .onTrack),
        (140, .onTrack),
        (120, .offTrack),
        (36, .offTrack),
    ])
    func track144(heard: Int, expected: VoiceProgress.Status) {
        #expect(SpokenNumber.track(heard: heard, answer: 144) == expected)
    }
}
