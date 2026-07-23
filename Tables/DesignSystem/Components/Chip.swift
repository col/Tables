import SwiftUI

/// Full pill, used for the length options on the setup screen.
struct Chip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Color.paper : Color.ink)
                .padding(.vertical, 11)
                .padding(.horizontal, Metrics.space4)
                .background(isSelected ? Color.ink : Color.paper)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.ink : Color.line, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: isSelected)
    }
}

/// A non-interactive status pill, e.g. "Soon" against the Voice answer mode.
struct StatusChip: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Typography.ui(11, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color.lilacText)
            .padding(.vertical, 3)
            .padding(.horizontal, Metrics.space3)
            .background(Color.lilacTint)
            .clipShape(Capsule())
    }
}
