import Foundation

/// Lightweight, toggleable tracing for voice recognition — for hand-debugging
/// on device. Compiled out entirely in release; in debug it is silent unless
/// enabled. The default reads the `-voiceDebug` launch argument, so it can be
/// switched on from the Xcode scheme without a code change (set
/// `VoiceLog.isEnabled = true` to force it).
///
/// `nonisolated`: callable from the nonisolated parser and the @MainActor
/// recogniser/controller alike.
nonisolated enum VoiceLog {
    #if DEBUG
    nonisolated(unsafe) static var isEnabled =
        ProcessInfo.processInfo.arguments.contains("-voiceDebug")
    #endif

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        print("[Voice] \(message())")
        #endif
    }
}
