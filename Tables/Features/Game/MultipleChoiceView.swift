import SwiftUI

struct MultipleChoiceView: View {
    let session: GameSession

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.space3), count: 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.space3) {
            ForEach(session.options, id: \.self) { value in
                TileButton(
                    label: "\(value)",
                    state: state(for: value),
                    font: Typography.display(26, relativeTo: .title2),
                    identifier: "game.option.\(value)"
                ) {
                    session.submit(value, now: Date())
                }
                .accessibilityLabel("\(value)")
            }
        }
    }

    /// The tapped tile turns sage or blush. In Revision the correct tile also
    /// turns sage, so a wrong answer still teaches the right one.
    private func state(for value: Int) -> TileState {
        guard let picked = session.pickedValue else { return .neutral }
        if value == picked {
            return value == session.fact.answer ? .correct : .incorrect
        }
        if session.revealAnswer && value == session.fact.answer {
            return .correct
        }
        return .neutral
    }
}
