import SwiftUI

/// Paper fill, hairline warm border, no shadow. The system is nearly flat.
struct Card<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: Metrics.strokeCard)
            }
    }
}
