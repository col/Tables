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
    // Hoisted into @State so the publisher is created once per view identity,
    // not rebuilt on every ~50ms body re-evaluation.
    @State private var ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(config: GameConfig) {
        self.config = config
    }

    var body: some View {
        PhoneColumn {
            VStack(spacing: 0) {
                if let session {
                    header(session)
                    content(session)
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
        // 20Hz is enough for a whole-second clock and a 240ms cross-fade.
        .onReceive(ticker) { now in
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
            config: effectiveConfig,
            store: SwiftDataProgressStore(context: modelContext),
            optionCount: settings.multipleChoiceOptionCount,
            feedback: player,
            rng: SystemRandomNumberGenerator()
        )
        created.start(now: Date())
        session = created
    }

    /// A UI smoke test cannot sit out a real 30–120s countdown, so the
    /// `-uiTesting` launch argument caps it to a few seconds. This is the only
    /// place in the app that reads the flag, and it only shortens a countdown.
    private var effectiveConfig: GameConfig {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting"),
              case .seconds = config.length else { return config }
        var shortened = config
        shortened.length = .seconds(8)
        return shortened
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
            .accessibilityIdentifier("game.status")
    }

    private func content(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Metrics.space4)

            problem(session)

            // Reserved space, so nothing shifts when feedback appears.
            reviewControls(session)
                .frame(height: 40)
                .padding(.top, Metrics.space3)

            Spacer(minLength: Metrics.space4)

            Group {
                switch config.answerMode {
                case .multipleChoice:
                    MultipleChoiceView(session: session)
                case .numberPad:
                    NumberPadView(session: session)
                case .voice:
                    // TODO(Task 7): replace with VoiceInputView(session: session)
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

    /// The problem, hero-sized. When the answer is revealed it settles left and
    /// "= 56" fades in beside it.
    private func problem(_ session: GameSession) -> some View {
        let size: CGFloat = config.answerMode == .multipleChoice ? 56 : 52
        return HStack(spacing: Metrics.space4) {
            Text(session.fact.display)
                .font(Typography.display(size, relativeTo: .largeTitle))
                .foregroundStyle(Color.ink)

            if session.revealAnswer {
                Text(session.fact.answerReveal)
                    .font(Typography.display(size, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ink)
                    .transition(.opacity.combined(with: .offset(x: -10)))
            }
        }
        .opacity(session.isFadingOut ? 0 : 1)
        .animation(
            Motion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
            value: session.isFadingOut
        )
        .animation(
            Motion.animation(Motion.revealAnimation, reduceMotion: reduceMotion),
            value: session.revealAnswer
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game.problem")
    }

    /// Reserved strip below the problem: a praise / "try again" pill after most
    /// answers, or an interactive "Try again" button while reviewing a wrong
    /// Revision answer.
    @ViewBuilder
    private func reviewControls(_ session: GameSession) -> some View {
        switch session.phase {
        case .feedback(let isCorrect, let text):
            Text(text)
                .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isCorrect ? Color.sageText : Color.blushText)
                .padding(.vertical, 7)
                .padding(.horizontal, Metrics.space4)
                .background(isCorrect ? Color.sageTint : Color.blushTint)
                .clipShape(Capsule())
                .transition(.opacity)
        case .reviewing:
            Button {
                session.tryAgain(now: Date())
            } label: {
                Text("Try again")
                    .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.ink)
                    .padding(.vertical, 9)
                    .padding(.horizontal, Metrics.space6)
                    .overlay {
                        Capsule().strokeBorder(Color.ink, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityIdentifier("game.tryagain")
        default:
            Color.clear
        }
    }
}
