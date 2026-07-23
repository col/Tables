import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// Uppercase RRGGBB, for token verification in tests.
    var hexString: String {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X",
                      Int((r * 255).rounded()),
                      Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
        #else
        return ""
        #endif
    }

    // Base neutrals — warm paper and soft ink.
    static let paper = Color(hex: 0xFBFAF7)
    static let canvas = Color(hex: 0xF2EFE8)
    static let tileNeutral = Color(hex: 0xEFEBE3)
    static let line = Color(hex: 0xDDD8CE)
    static let border = Color(hex: 0xE4E0D8)
    static let divider = Color(hex: 0xF0EDE6)
    static let ink = Color(hex: 0x2B2A28)
    static let inkSoft = Color(hex: 0x6B6862)
    static let inkMuted = Color(hex: 0x8A867E)

    // Feedback and brand hues: saturated fill, pale tint, deep text.
    static let sage = Color(hex: 0xB7CDAE)
    static let sageTint = Color(hex: 0xE8EFE2)
    static let sageText = Color(hex: 0x33472C)

    static let butter = Color(hex: 0xF0D999)
    static let butterTint = Color(hex: 0xFAF1D6)
    static let butterText = Color(hex: 0x665012)

    static let blush = Color(hex: 0xE9AFAB)
    static let blushTint = Color(hex: 0xF7E3E1)
    static let blushText = Color(hex: 0x6E2E2A)

    static let sky = Color(hex: 0xA9C7E0)
    static let skyTint = Color(hex: 0xE4EEF6)
    static let skyText = Color(hex: 0x274963)

    static let lilac = Color(hex: 0xC7BEE0)
    static let lilacTint = Color(hex: 0xEEEAF6)
    static let lilacText = Color(hex: 0x453963)

    static let clay = Color(hex: 0xB24A3F)
}
