import SwiftUI

/// A custom pad, never the system keyboard — the app's typography and spacing
/// have to hold all the way through the game.
struct NumberPadView: View {
    let session: GameSession

    private enum Key: Hashable {
        case digit(Int)
        case delete
        case submit
    }

    private static let keys: [Key] = [
        .digit(1), .digit(2), .digit(3),
        .digit(4), .digit(5), .digit(6),
        .digit(7), .digit(8), .digit(9),
        .delete, .digit(0), .submit
    ]

    /// The entry display echoes the answer state: sage on a correct answer,
    /// blush while a wrong answer is shown (Countdown feedback or the Revision
    /// "Try again" review).
    private var isWrong: Bool {
        switch session.phase {
        case .feedback(let isCorrect, _): !isCorrect
        case .reviewing: true
        default: false
        }
    }

    private var isCorrect: Bool {
        if case .feedback(true, _) = session.phase { return true }
        return false
    }

    private var displayBorder: Color {
        if isCorrect { return .sage }
        if isWrong { return .blush }
        return .line
    }

    var body: some View {
        VStack(spacing: Metrics.space3 + 2) {
            entryDisplay

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.space2 + 2), count: 3),
                spacing: Metrics.space2 + 2
            ) {
                ForEach(Self.keys, id: \.self) { key in
                    keyButton(key)
                }
            }
        }
    }

    private var entryDisplay: some View {
        Text(session.padValue.isEmpty ? " " : session.padValue)
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
            .accessibilityLabel(session.padValue.isEmpty ? "No answer entered" : "Answer \(session.padValue)")
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        Button {
            switch key {
            case .digit(let value): session.padAppend(value, now: Date())
            case .delete: session.padDelete()
            case .submit: session.padSubmit(now: Date())
            }
        } label: {
            label(for: key)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(background(for: key))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusKey, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radiusKey, style: .continuous)
                        .strokeBorder(stroke(for: key), lineWidth: Metrics.strokeTile)
                }
        }
        .buttonStyle(.plain)
        .disabled(key == .submit && !session.canSubmitPad)
        .opacity(key == .submit && !session.canSubmitPad ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel(for: key))
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .digit(let value):
            Text("\(value)")
                .font(Typography.display(24, relativeTo: .title2))
                .foregroundStyle(Color.ink)
        case .delete:
            // The bundled fonts have no glyph for ⌫, so this is an SF Symbol.
            Image(systemName: "delete.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.inkSoft)
        case .submit:
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.paper)
        }
    }

    private func background(for key: Key) -> Color {
        switch key {
        case .digit: .paper
        case .delete: .tileNeutral
        case .submit: .ink
        }
    }

    private func stroke(for key: Key) -> Color {
        switch key {
        case .digit: .line
        case .delete: .border
        case .submit: .ink
        }
    }

    private func accessibilityLabel(for key: Key) -> String {
        switch key {
        case .digit(let value): "\(value)"
        case .delete: "Delete"
        case .submit: "Submit answer"
        }
    }
}
