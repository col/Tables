import Foundation

/// Lightweight, toggleable tracing for voice recognition — for hand-debugging
/// on device. Compiled out entirely in release; in debug it is silent unless
/// enabled. The default reads the `-voiceDebug` launch argument, so it can be
/// switched on from the Xcode scheme without a code change (set
/// `VoiceLog.isEnabled = true` to force it).
///
/// Each line is stamped with `t=` (monotonic seconds since the first log line)
/// and `+` (milliseconds since the previous line), so the actual settle waits
/// and inter-partial gaps are visible directly — e.g. a ~1200 ms `+` between a
/// "heard" line and its "submit" line is the on-track wait playing out.
///
/// `nonisolated`: callable from the nonisolated parser and the @MainActor
/// recogniser/controller alike.
nonisolated enum VoiceLog {
    #if DEBUG
    nonisolated(unsafe) static var isEnabled =
        ProcessInfo.processInfo.arguments.contains("-voiceDebug")

    /// Monotonic clock reference points. `ContinuousClock` keeps ticking across
    /// suspensions, so gaps reflect real elapsed time.
    nonisolated(unsafe) private static var start: ContinuousClock.Instant?
    nonisolated(unsafe) private static var last: ContinuousClock.Instant?
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        let now = ContinuousClock.now
        if start == nil { start = now }
        let elapsed = now - (start ?? now)
        let delta = last.map { now - $0 } ?? .zero
        last = now
        let stamp = String(format: "t=%.3fs +%.0fms", seconds(elapsed), millis(delta))
        print("[Voice \(stamp)] \(message())")
        #endif
    }

    #if DEBUG
    private static func millis(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1_000_000_000_000_000
    }

    private static func seconds(_ d: Duration) -> Double { millis(d) / 1000 }
    #endif
}
