import AVFoundation
import UIKit

@MainActor
protocol FeedbackPlaying: AnyObject {
    func correct()
    func incorrect()
}

/// Used in tests and previews, where audio and haptics are noise.
@MainActor
final class SilentFeedbackPlayer: FeedbackPlaying {
    init() {}
    func correct() {}
    func incorrect() {}
}

/// Haptics plus two synthesised tones.
///
/// The tones are generated rather than shipped as assets: there is nothing to
/// licence, nothing to bundle, and the result is a soft sine rather than a
/// game-show sting.
@MainActor
final class FeedbackPlayer: FeedbackPlaying {
    private let settings: AppSettings
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var correctBuffer: AVAudioPCMBuffer?
    private var incorrectBuffer: AVAudioPCMBuffer?
    private var isEngineReady = false

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func correct() {
        if settings.hapticsEnabled {
            impact.impactOccurred()
        }
        play(\.correctBuffer)
    }

    func incorrect() {
        if settings.hapticsEnabled {
            notification.notificationOccurred(.warning)
        }
        play(\.incorrectBuffer)
    }

    func prepare() {
        impact.prepare()
        notification.prepare()
    }

    private func play(_ keyPath: KeyPath<FeedbackPlayer, AVAudioPCMBuffer?>) {
        guard settings.soundEnabled else { return }
        startEngineIfNeeded()
        guard let buffer = self[keyPath: keyPath] else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func startEngineIfNeeded() {
        guard !isEngineReady else { return }
        isEngineReady = true

        // .ambient means the hardware silent switch and any music already
        // playing both win. A practice app should never take over the device.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        correctBuffer = Self.tone(frequency: 880, duration: 0.16, format: format)
        incorrectBuffer = Self.tone(frequency: 320, duration: 0.18, format: format)
        try? engine.start()
    }

    /// Fast attack, gentle exponential decay — a soft knock rather than a beep.
    private static func tone(
        frequency: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let attackFrames = sampleRate * 0.005
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let attack = min(1, Double(frame) / attackFrames)
            let decay = exp(-6 * time / duration)
            channel[frame] = Float(sin(2 * .pi * frequency * time) * attack * decay * 0.22)
        }
        return buffer
    }
}
