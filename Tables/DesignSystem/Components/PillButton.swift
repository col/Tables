import SwiftUI

struct PillButton: View {
    enum Style {
        case primary
        case ghost
    }

    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let identifier: String?
    private let action: () -> Void

    init(
        _ title: String,
        style: Style = .primary,
        isEnabled: Bool = true,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.ui(style == .primary ? 17 : 15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(style == .primary ? Color.paper : Color.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, style == .primary ? Metrics.space4 : Metrics.space2)
                .background(style == .primary ? Color.ink : Color.clear)
                .clipShape(Capsule())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityIdentifier(identifier ?? "")
    }
}
