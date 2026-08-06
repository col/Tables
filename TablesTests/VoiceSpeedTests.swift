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
        (VoiceSpeed.fastest, "Fastest", 100, 500),
        (.fast, "Fast", 250, 650),
        (.normal, "Normal", 400, 800),
        (.slow, "Slow", 550, 950),
        (.slowest, "Slowest", 700, 1100),
    ])
    func table(speed: VoiceSpeed, label: String, short: Int, onTrack: Int) {
        #expect(speed.label == label)
        #expect(speed.shortWait == .milliseconds(short))
        #expect(speed.onTrackWait == .milliseconds(onTrack))
    }
}
