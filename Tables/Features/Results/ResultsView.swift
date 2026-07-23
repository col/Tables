import SwiftUI

struct ResultsView: View {
    @Environment(AppRouter.self) private var router

    let summary: GameSession.Summary

    private var now: Date { Date() }

    private var unit: String {
        summary.config.mode == .countdown ? "correct answers" : "answered correctly"
    }

    var body: some View {
        PhoneColumn {
            VStack(spacing: 0) {
                Eyebrow(summary.config.summary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text("\(summary.score)")
                        .font(Typography.display(80, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ink)
                    Text(unit)
                        .font(Typography.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(.top, Metrics.space5)
                .padding(.bottom, Metrics.space4)
                .accessibilityElement(children: .combine)

                banner

                Eyebrow("Your best runs")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Metrics.space5)
                    .padding(.bottom, Metrics.space2 + 2)

                ScrollView {
                    VStack(spacing: Metrics.space1 + 2) {
                        ForEach(Array(summary.board.topRuns.enumerated()), id: \.element.date) { index, run in
                            row(rank: index + 1, run: run)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: Metrics.space2 + 2) {
                    PillButton("Play again") { router.playAgain() }
                    PillButton("Back home", style: .ghost) { router.goHome() }
                }
                .padding(.top, Metrics.space3 + 2)
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space3 + 2)
            .padding(.bottom, Metrics.space5)
        }
    }

    private var banner: some View {
        Text(summary.board.bannerText)
            .font(Typography.ui(13.5, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(summary.board.isNewBest ? Color.sageText : Color.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.space2 + 2)
            .padding(.horizontal, Metrics.space4)
            .background(summary.board.isNewBest ? Color.sageTint : Color.tileNeutral)
            .clipShape(Capsule())
    }

    private func row(rank: Int, run: RunRecord) -> some View {
        let isCurrent = run == summary.board.current

        return HStack(spacing: Metrics.space3 + 2) {
            Text("\(rank)")
                .font(Typography.display(15, relativeTo: .subheadline))
                .foregroundStyle(isCurrent ? Color.sageText : Color.inkMuted)
                .frame(width: 16, alignment: .leading)

            Text(ScoreBoard.relativeDateLabel(for: run.date, isCurrentRun: isCurrent, now: now))
                .font(Typography.ui(13, relativeTo: .footnote))
                .foregroundStyle(isCurrent ? Color.sageText : Color.ink)

            Spacer()

            Text("\(run.score)")
                .font(Typography.display(20, relativeTo: .title3))
                .foregroundStyle(isCurrent ? Color.sageText : Color.ink)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Metrics.space3 + 2)
        .background(isCurrent ? Color.sage : Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
        .overlay {
            if !isCurrent {
                RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: Metrics.strokeCard)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
