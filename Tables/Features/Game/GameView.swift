import SwiftUI
import SwiftData
import Combine

struct GameView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let config: GameConfig
    @State private var session: GameSession?

    init(config: GameConfig) {
        self.config = config
    }

    var body: some View {
        PhoneColumn {
            VStack(spacing: 0) {
                if let session {
                    header(session)
                    content(session)
                    PillButton(session.endLabel, style: .ghost) {
                        if session.endEarly(now: Date()) == .finished {
                            if let summary = session.summary { router.showResults(summary) }
                        } else {
                            router.goHome()
                        }
                    }
                    .padding(.bottom, Metrics.space3 + 2)
                } else {
                    Color.canvas
                }
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space5)
        }
        .onAppear(perform: startIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            guard let session else { return }
            if phase == .active { session.resume(now: Date()) } else { session.pause(now: Date()) }
        }
        // 20Hz is enough for a whole-second clock and a 240ms cross-fade, and
        // cheap enough not to matter.
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { now in
            guard let session, session.phase != .finished else { return }
            session.tick(now: now)
            if session.phase == .finished, let summary = session.summary {
                router.showResults(summary)
            }
        }
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        let player = FeedbackPlayer(settings: settings)
        // Warming the haptic generators here keeps the first tap as crisp as
        // the rest.
        player.prepare()
        let created = GameSession(
            config: config,
            store: SwiftDataProgressStore(context: modelContext),
            optionCount: settings.multipleChoiceOptionCount,
            feedback: player,
            rng: SystemRandomNumberGenerator()
        )
        created.start(now: Date())
        session = created
    }

    private func header(_ session: GameSession) -> some View {
        HStack {
            BackButton { router.goHome() }
            Spacer()
            Eyebrow(config.mode.title)
            Spacer()
            statusPill(session)
        }
        .padding(.bottom, Metrics.space1 + 2)
    }

    @ViewBuilder
    private func statusPill(_ session: GameSession) -> some View {
        let isCountdown = config.mode == .countdown
        let text = isCountdown ? session.timeText : session.revisionProgressText
        let isLow = isCountdown && session.isLowTime

        Text(text)
            .font(Typography.display(19, relativeTo: .headline))
            .foregroundStyle(isLow ? Color.blushText : Color.skyText)
            .monospacedDigit()
            .padding(.vertical, Metrics.space2)
            .padding(.horizontal, isCountdown ? Metrics.space4 + 2 : Metrics.space4)
            .background(isLow ? Color.blush : Color.skyTint)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: isLow)
            .frame(minWidth: 64)
            .accessibilityLabel(isCountdown ? "\(session.secondsRemaining) seconds left" : "\(session.answered) answered")
    }

    private func content(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Metrics.space4)

            Text(session.fact.display)
                .font(Typography.display(config.answerMode == .multipleChoice ? 56 : 52, relativeTo: .largeTitle))
                .foregroundStyle(Color.ink)
                .opacity(session.isFadingOut ? 0 : 1)
                .animation(
                    Motion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
                    value: session.isFadingOut
                )

            // Reserved space, so nothing shifts when feedback appears.
            feedbackPill(session)
                .frame(height: 34)
                .padding(.top, Metrics.space3)

            Spacer(minLength: Metrics.space4)

            Group {
                switch config.answerMode {
                case .multipleChoice:
                    MultipleChoiceView(session: session)
                case .numberPad:
                    NumberPadView(session: session)
                }
            }
            .opacity(session.isFadingOut ? 0 : 1)
            .animation(
                Motion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
                value: session.isFadingOut
            )

            Spacer(minLength: Metrics.space4)
        }
    }

    @ViewBuilder
    private func feedbackPill(_ session: GameSession) -> some View {
        if case .feedback(let isCorrect, let text) = session.phase {
            Text(text)
                .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isCorrect ? Color.sageText : Color.blushText)
                .padding(.vertical, 7)
                .padding(.horizontal, Metrics.space4)
                .background(isCorrect ? Color.sageTint : Color.blushTint)
                .clipShape(Capsule())
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}

// Replaced by Task 16.
struct NumberPadView: View {
    let session: GameSession
    var body: some View { Color.clear }
}
