import SwiftUI

struct SetupView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SetupModel

    init(mode: GameMode) {
        _model = State(initialValue: SetupModel(mode: mode))
    }

    var body: some View {
        PhoneColumn {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.space3 + 2) {
                    BackButton { router.goHome() }
                    Text(model.mode.title)
                        .font(Typography.display(27, relativeTo: .title))
                        .foregroundStyle(Color.ink)
                }
                .padding(.bottom, Metrics.space4 + 2)

                ScrollView {
                    VStack(spacing: Metrics.space2 + 2) {
                        tablesSection
                        answerModeSection
                        lengthSection
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                PillButton(
                    "Start \(model.mode.lowercasedTitle)",
                    isEnabled: model.config.isStartable
                ) {
                    router.startGame(model.config)
                }
                .padding(.top, Metrics.space3 + 2)
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space5)
        }
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: model.openSection)
    }

    private func section<Content: View>(
        _ id: SetupModel.Section,
        label: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Button { model.toggle(section: id) } label: {
                    HStack {
                        Eyebrow(label)
                        Spacer(minLength: Metrics.space3)
                        Text(summary)
                            .font(Typography.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Color.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(Metrics.space4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if model.openSection == id {
                    content()
                        .padding(.horizontal, Metrics.space4)
                        .padding(.bottom, Metrics.space4)
                }
            }
        }
    }

    private var tablesSection: some View {
        section(.tables, label: "Tables", summary: model.config.tablesSummary) {
            VStack(spacing: Metrics.space2 + 2) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.space2), count: 4),
                    spacing: Metrics.space2
                ) {
                    ForEach(1...12, id: \.self) { number in
                        TileButton(
                            label: "\(number)",
                            state: model.tables.contains(number) ? .selected : .neutral,
                            font: Typography.display(20, relativeTo: .title3),
                            verticalPadding: Metrics.space3
                        ) {
                            model.toggle(table: number)
                        }
                        .accessibilityLabel("\(number) times table")
                        .accessibilityAddTraits(model.tables.contains(number) ? .isSelected : [])
                    }
                }

                Button { model.toggleAll() } label: {
                    Text(model.selectAllLabel)
                        .font(Typography.ui(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.skyText)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var answerModeSection: some View {
        section(.answerMode, label: "Answer mode", summary: model.answerMode.title) {
            VStack(spacing: Metrics.space2) {
                ForEach(AnswerMode.allCases, id: \.self) { mode in
                    answerRow(mode)
                }
                voiceRow
            }
        }
    }

    private func answerRow(_ mode: AnswerMode) -> some View {
        let isSelected = model.answerMode == mode
        return Button { model.answerMode = mode } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                    Text(mode.subtitle)
                        .font(Typography.ui(12, relativeTo: .caption))
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer()
                radioDot(isSelected: isSelected)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, Metrics.space3 + 2)
            .background(isSelected ? Color.skyTint : Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                    .strokeBorder(isSelected ? Color.sky : Color.border, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func radioDot(isSelected: Bool) -> some View {
        Circle()
            .fill(isSelected ? Color.sky : Color.clear)
            .frame(width: 20, height: 20)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.skyTint : Color.line, lineWidth: isSelected ? 5 : 1.5)
            }
            .overlay {
                if isSelected { Circle().strokeBorder(Color.sky, lineWidth: 1.5) }
            }
    }

    private var voiceRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice")
                    .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.inkSoft)
                Text("Say it out loud")
                    .font(Typography.ui(12, relativeTo: .caption))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            StatusChip("Soon")
        }
        .padding(.vertical, 13)
        .padding(.horizontal, Metrics.space3 + 2)
        .background(Color.tileNeutral)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1.5)
        }
        .opacity(0.75)
        .accessibilityLabel("Voice. Say it out loud. Coming soon.")
    }

    private var lengthSection: some View {
        section(.length, label: model.mode.lengthSectionLabel, summary: model.length.summary) {
            FlowRow(spacing: Metrics.space2) {
                ForEach(model.lengthOptions, id: \.self) { option in
                    Chip(option.chipLabel, isSelected: model.length == option) {
                        model.length = option
                    }
                }
            }
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: width, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
