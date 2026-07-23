import SwiftUI

/// Three pastel squares beside the wordmark. Reproduced from the design
/// project — this is the mark, not a placeholder for one.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Metrics.space2 + 2) {
            HStack(spacing: 3) {
                ForEach([Color.sage, .butter, .sky], id: \.self) { color in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color)
                        .frame(width: 15, height: 15)
                }
            }
            Text("Tables")
                .font(Typography.display(22, relativeTo: .title3))
                .foregroundStyle(Color.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tables")
    }
}
