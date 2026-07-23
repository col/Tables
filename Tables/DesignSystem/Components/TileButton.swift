import SwiftUI

/// The state → colour/stroke/text mapping for a tile.
enum TileState {
    case neutral
    case selected
    case correct
    case incorrect

    var fill: Color {
        switch self {
        case .neutral: .paper
        case .selected: .skyTint
        case .correct: .sage
        case .incorrect: .blush
        }
    }

    var stroke: Color {
        switch self {
        case .neutral: .line
        case .selected: .sky
        case .correct: .sage
        case .incorrect: .blush
        }
    }

    var text: Color {
        switch self {
        case .neutral: .ink
        case .selected: .skyText
        case .correct: .sageText
        case .incorrect: .blushText
        }
    }

    /// Only a tile the child just touched pops.
    var shouldPop: Bool {
        self == .correct || self == .incorrect
    }
}

/// A gently rounded square with a visible 2pt stroke. State is communicated by
/// fill colour above all else.
struct TileButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let label: String
    private let state: TileState
    private let font: Font
    private let verticalPadding: CGFloat
    private let identifier: String?
    private let action: () -> Void

    @State private var scale: CGFloat = 1

    init(
        label: String,
        state: TileState,
        font: Font,
        verticalPadding: CGFloat = 18,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.state = state
        self.font = font
        self.verticalPadding = verticalPadding
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundStyle(state.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(state.fill)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                        .strokeBorder(state.stroke, lineWidth: Metrics.strokeTile)
                }
                .scaleEffect(scale)
        }
        .accessibilityIdentifier(identifier ?? "")
        .buttonStyle(.plain)
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: state)
        .onChange(of: state) { _, newState in
            guard newState.shouldPop, !reduceMotion else { return }
            withAnimation(.easeOut(duration: Motion.pop / 2)) { scale = 1.12 }
            withAnimation(.easeIn(duration: Motion.pop / 2).delay(Motion.pop / 2)) { scale = 1 }
        }
    }
}
