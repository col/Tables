import SwiftUI

/// The `.voice` answer mode. Always listening while a question is shown; a
/// recognised number submits through the shared `session.submit` seam. The
/// mic pulses while listening and flashes the heard number, echoing the
/// number pad's sage/blush feedback so voice feels of a piece with the app.
struct VoiceInputView: View {
    let session: GameSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller: VoiceAnswerController?
    @State private var recognizer = SpeechAnswerRecognizer()
    @State private var permissionDenied = false
    @State private var fellBackToKeypad = false

    private var isWrong: Bool {
        switch session.phase {
        case .feedback(let ok, _): !ok
        case .reviewing: true
        default: false
        }
    }

    private var isCorrect: Bool {
        if case .feedback(true, _) = session.phase { return true }
        return false
    }

    var body: some View {
        Group {
            if fellBackToKeypad {
                // Permission was denied and the child chose to type instead.
                NumberPadView(session: session)
            } else if permissionDenied {
                deniedNotice
            } else {
                VStack(spacing: Metrics.space3 + 2) {
                    heardDisplay
                    micIndicator
                }
            }
        }
        .onAppear(perform: startIfNeeded)
        .onChange(of: session.phase) { _, _ in
            controller?.syncToPhase()
        }
        // No phase change fires when the game is abandoned mid-question, so
        // release the mic/engine explicitly as the view goes away.
        .onDisappear { controller?.stopListening() }
    }

    private func startIfNeeded() {
        guard controller == nil else {
            controller?.syncToPhase()
            return
        }
        let controller = VoiceAnswerController(session: session, recognizer: recognizer)
        self.controller = controller
        controller.requestAuthorization { granted in
            if granted {
                permissionDenied = false
                controller.syncToPhase()
            } else {
                permissionDenied = true
            }
        }
    }

    // MARK: Listening UI

    private var displayText: String {
        // Once answered, show the submitted number through the whole feedback
        // hold (it survives on the session as `pickedValue`), the same way the
        // number pad keeps the entered value on screen. `.heard` only shows in
        // the instant between recognition and submit.
        if session.phase != .asking, let picked = session.pickedValue {
            return String(picked)
        }
        if case .heard(let n) = controller?.display { return String(n) }
        return " "
    }

    private var displayBorder: Color {
        if isCorrect { return .sage }
        if isWrong { return .blush }
        return .line
    }

    private var heardDisplay: some View {
        Text(displayText)
            .font(Typography.display(34, relativeTo: .largeTitle))
            .foregroundStyle(isWrong ? Color.blushText : Color.ink)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isWrong ? Color.blushTint : Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                    .strokeBorder(displayBorder, lineWidth: Metrics.strokeTile)
            }
            .accessibilityLabel(displayText == " " ? "Listening" : "Heard \(displayText)")
    }

    private var isListening: Bool {
        if case .listening = controller?.display { return true }
        return false
    }

    private var micIndicator: some View {
        VStack(spacing: Metrics.space2) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(isListening ? Color.ink : Color.inkSoft)
                .scaleEffect(isListening && !reduceMotion ? 1.08 : 1.0)
                .animation(
                    Motion.animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        reduceMotion: reduceMotion
                    ),
                    value: isListening
                )
            Text("Say your answer")
                .font(Typography.ui(13, relativeTo: .footnote))
                .foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space4)
    }

    // MARK: Permission denied

    private var deniedNotice: some View {
        VStack(spacing: Metrics.space3) {
            Text("Voice needs microphone access")
                .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: Metrics.space2) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Use keypad") {
                    // Abandon voice for this game: stop the mic and switch the
                    // whole view to the number pad (handled in `body`).
                    controller?.stopListening()
                    fellBackToKeypad = true
                }
            }
            .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
        }
        .padding(.vertical, Metrics.space4)
    }
}
