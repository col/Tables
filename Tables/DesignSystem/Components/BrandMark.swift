import SwiftUI

/// The app icon, scaled down, beside the wordmark. This is the mark, not a
/// placeholder for one.
struct BrandMark: View {
    private let iconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: Metrics.space2 + 2) {
            Image("BrandIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                // Matches the iOS icon squircle proportion (~22.4% of the side).
//                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))
            Text("Tables")
                .font(Typography.display(22, relativeTo: .title3))
                .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tables")
    }
}
