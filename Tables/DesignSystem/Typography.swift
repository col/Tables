import SwiftUI

/// Two families: Zilla Slab for numbers, problems and headings; Libre Franklin
/// for all interface text. Every size is registered relative to a system text
/// style so Dynamic Type still scales the app.
enum Typography {
    enum UIFontWeight {
        case regular, semibold
    }

    static let displayFontName = "ZillaSlab-SemiBold"

    static func uiFontName(for weight: UIFontWeight) -> String {
        switch weight {
        case .regular: "LibreFranklin-Regular"
        case .semibold: "LibreFranklin-SemiBold"
        }
    }

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(displayFontName, size: size, relativeTo: style)
    }

    static func ui(
        _ size: CGFloat,
        weight: UIFontWeight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        .custom(uiFontName(for: weight), size: size, relativeTo: style)
    }

    /// Tracking for small uppercase "eyebrow" labels — 0.16em at label size.
    static let capsTracking: CGFloat = 1.8
}
