import Testing
@testable import Tables

struct VoiceSpeedTests {

    @Test("cases are ordered fastest to slowest by raw value")
    func order() {
        #expect(VoiceSpeed.allCases == [.fastest, .fast, .normal, .slow, .slowest])
        #expect(VoiceSpeed.fastest.rawValue == 0)
        #expect(VoiceSpeed.slowest.rawValue == 4)
    }

    @Test("durations and labels match the table", arguments: [
        (VoiceSpeed.fastest, "Fastest", 200, 600),
        (.fast, "Fast", 300, 700),
        (.normal, "Normal", 400, 800),
        (.slow, "Slow", 500, 900),
        (.slowest, "Slowest", 600, 1000),
    ])
    func table(speed: VoiceSpeed, label: String, short: Int, onTrack: Int) {
        #expect(speed.label == label)
        #expect(speed.shortWait == .milliseconds(short))
        #expect(speed.onTrackWait == .milliseconds(onTrack))
    }
}
