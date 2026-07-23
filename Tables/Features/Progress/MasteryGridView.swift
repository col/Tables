import SwiftUI
import SwiftData

extension MasteryLevel {
    var fill: Color {
        switch self {
        case .mastered: .sage
        case .gettingThere: .butter
        case .notYet: .tileNeutral
        }
    }

    /// Only the empty state needs an outline to read as a cell at all.
    var needsOutline: Bool { self == .notYet }
}

struct MasteryGridView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query private var stats: [FactStat]

    private var levels: [String: MasteryLevel] {
        Dictionary(uniqueKeysWithValues: stats.map { ($0.key, Mastery.level(for: $0.history)) })
    }

    var body: some View {
        PhoneColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Metrics.space3 + 2) {
                        BackButton { router.goHome() }
                        Text("Your tables")
                            .font(Typography.display(27, relativeTo: .title))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.bottom, Metrics.space2 + 2)

                    Text("Track your progress and see which tables to revise. How many can you master?")
                        .font(Typography.ui(14, relativeTo: .subheadline))
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(3)
                        .padding(.bottom, Metrics.space4 + 2)

                    Card {
                        VStack(alignment: .leading, spacing: Metrics.space3 + 2) {
                            legend
                            grid
                        }
                        .padding(Metrics.space4)
                    }
                }
                .padding(.horizontal, Metrics.space5 + 2)
                .padding(.top, Metrics.space2)
                .padding(.bottom, Metrics.space6)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Metrics.space3 + 2) {
            ForEach([MasteryLevel.mastered, .gettingThere, .notYet], id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(level.fill)
                        .frame(width: 12, height: 12)
                        .overlay {
                            if level.needsOutline {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color.line, lineWidth: 1)
                            }
                        }
                    Text(level.legendLabel)
                        .font(Typography.ui(12, relativeTo: .caption))
                        .foregroundStyle(Color.inkSoft)
                }
            }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(width: 14, height: 1)
                ForEach(1...12, id: \.self) { column in
                    axisLabel("\(column)", color: .inkMuted)
                }
            }
            ForEach(1...12, id: \.self) { row in
                GridRow {
                    axisLabel("\(row)", color: .inkSoft)
                    ForEach(1...12, id: \.self) { column in
                        cell(a: row, b: column)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func axisLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.ui(9, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
    }

    private func cell(a: Int, b: Int) -> some View {
        let level = levels[Fact(a: a, b: b).key] ?? .notYet
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(level.fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if level.needsOutline {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.line, lineWidth: 1)
                }
            }
    }

    /// The grid is 144 cells; reading it out one by one would be useless.
    private var accessibilitySummary: String {
        let all = levels.values
        let mastered = all.filter { $0 == .mastered }.count
        let gettingThere = all.filter { $0 == .gettingThere }.count
        return "Mastery grid. \(mastered) of 144 facts mastered, \(gettingThere) getting there."
    }
}
