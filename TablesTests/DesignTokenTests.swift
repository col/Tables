import Testing
import SwiftUI
@testable import Tables

struct DesignTokenTests {

    @Test("palette hex values match the design system tokens")
    func paletteMatchesTokens() {
        #expect(Color.canvas.hexString == "F2EFE8")
        #expect(Color.paper.hexString == "FBFAF7")
        #expect(Color.ink.hexString == "2B2A28")
        #expect(Color.sage.hexString == "B7CDAE")
        #expect(Color.sageTint.hexString == "E8EFE2")
        #expect(Color.sageText.hexString == "33472C")
        #expect(Color.butter.hexString == "F0D999")
        #expect(Color.blush.hexString == "E9AFAB")
        #expect(Color.sky.hexString == "A9C7E0")
        #expect(Color.skyTint.hexString == "E4EEF6")
        #expect(Color.skyText.hexString == "274963")
        #expect(Color.lilacTint.hexString == "EEEAF6")
        #expect(Color.clay.hexString == "B24A3F")
    }

    @Test("spacing follows the 4pt rhythm from the token set")
    func spacingRhythm() {
        #expect(Metrics.space1 == 4)
        #expect(Metrics.space4 == 16)
        #expect(Metrics.space6 == 26)
        #expect(Metrics.space10 == 72)
        #expect(Metrics.hitMin == 44)
    }

    @Test("radii match the token set")
    func radii() {
        #expect(Metrics.radiusSwatch == 6)
        #expect(Metrics.radiusKey == 8)
        #expect(Metrics.radiusTile == 10)
        #expect(Metrics.radiusCard == 14)
        #expect(Metrics.strokeTile == 2)
        #expect(Metrics.strokeCard == 1)
    }

    @Test("Reduce Motion suppresses animation")
    func reduceMotionSuppressesAnimation() {
        #expect(Motion.animation(Motion.popAnimation, reduceMotion: true) == nil)
        #expect(Motion.animation(Motion.popAnimation, reduceMotion: false) != nil)
    }

    @Test("typography resolves the bundled families")
    func typographyResolvesBundledFamilies() {
        #expect(Typography.displayFontName == "ZillaSlab-SemiBold")
        #expect(Typography.uiFontName(for: .regular) == "LibreFranklin-Regular")
        #expect(Typography.uiFontName(for: .semibold) == "LibreFranklin-SemiBold")
    }
}
