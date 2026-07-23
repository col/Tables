import SwiftUI

/// Caps the content column on iPad. The design is drawn for a phone; a
/// stretched phone layout is not the same design.
struct PhoneColumn<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content.frame(maxWidth: Metrics.contentMaxWidth)
            Spacer(minLength: 0)
        }
        .background(Color.canvas)
    }
}

struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        PhoneColumn {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, Metrics.space7)

                Text("What do you want\nto practise?")
                    .font(Typography.display(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)

                Text("Test yourself against the clock, or take your time and revise.")
                    .font(Typography.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Color.inkSoft)
                    .lineSpacing(3)
                    .padding(.top, Metrics.space2)
                    .padding(.bottom, Metrics.space6)

                VStack(spacing: Metrics.space3 + 2) {
                    countdownCard
                    revisionCard
                }

                Spacer(minLength: Metrics.space5)

                progressRow
            }
            .padding(.horizontal, Metrics.space6 - 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space6)
        }
        .sheet(isPresented: Binding(
            get: { router.isShowingSettings },
            set: { router.isShowingSettings = $0 }
        )) {
            SettingsView()
        }
    }

    private var header: some View {
        HStack {
            BrandMark()
            Spacer()
            Button { router.isShowingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color.inkSoft)
                    .frame(width: Metrics.hitMin, height: Metrics.hitMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        }
    }

    private var countdownCard: some View {
        modeCard(
            eyebrow: "Beat the clock",
            title: "Countdown",
            body: "Answer as many as you can before the timer runs out.",
            tint: .skyTint,
            textColor: .skyText
        ) {
            Text("60")
                .font(Typography.display(44, relativeTo: .largeTitle))
                .foregroundStyle(Color.sky)
        } action: {
            router.openSetup(.countdown)
        }
        .accessibilityIdentifier("home.countdown")
    }

    private var revisionCard: some View {
        modeCard(
            eyebrow: "No timer",
            title: "Revision",
            body: "Practise the tables you find tricky without the pressure of a timer.",
            tint: .sageTint,
            textColor: .sageText
        ) {
            // Indices, not values — the opacities repeat, and duplicate ForEach
            // ids make SwiftUI drop views.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 2), spacing: 3) {
                ForEach(Array([1.0, 0.5, 0.5, 1.0].enumerated()), id: \.offset) { _, opacity in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.sage.opacity(opacity))
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 31)
        } action: {
            router.openSetup(.revision)
        }
        .accessibilityIdentifier("home.revision")
    }

    private func modeCard<Motif: View>(
        eyebrow: String,
        title: String,
        body: String,
        tint: Color,
        textColor: Color,
        @ViewBuilder motif: () -> Motif,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Metrics.space3) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(eyebrow, color: textColor.opacity(0.85))
                    Text(title)
                        .font(Typography.display(27, relativeTo: .title))
                        .foregroundStyle(textColor)
                        .padding(.top, 6)
                    Text(body)
                        .font(Typography.ui(13, relativeTo: .footnote))
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                Spacer(minLength: Metrics.space2)
                motif()
            }
            .padding(.vertical, Metrics.space5)
            .padding(.horizontal, Metrics.space4 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(body)")
    }

    private var progressRow: some View {
        Button { router.openProgress() } label: {
            HStack {
                Eyebrow("Progress")
                Spacer()
                HStack(spacing: Metrics.space1 + 2) {
                    Text("Your tables")
                    Image(systemName: "arrow.right")
                }
                .font(Typography.ui(13.5, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.skyText)
            }
            .padding(.top, Metrics.space5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.progress")
    }
}
