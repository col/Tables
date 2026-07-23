import SwiftUI

struct BackButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: Metrics.hitMin, height: Metrics.hitMin)
                .background(Color.paper)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color.border, lineWidth: Metrics.strokeCard) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
