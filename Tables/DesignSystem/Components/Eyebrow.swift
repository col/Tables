import SwiftUI

/// Small tracked caps label. The only place uppercase is used in the app.
struct Eyebrow: View {
    private let text: String
    private let color: Color

    init(_ text: String, color: Color = .inkMuted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Typography.ui(11, weight: .semibold, relativeTo: .caption))
            .tracking(Typography.capsTracking)
            .foregroundStyle(color)
    }
}
