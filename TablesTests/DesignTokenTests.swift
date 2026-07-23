import Testing
import SwiftUI
@testable import Tables

struct DesignTokenTests {

    @Test("palette hex values match the design system tokens")
    func paletteMatchesTokens() {
        #expect(Color.canvas.hexString == "F2EFE8")
        #expect(Color.paper.hexString == "FBFAF7")
        #expect(Color.tileNeutral.hexString == "EFEBE3")
        #expect(Color.line.hexString == "DDD8CE")
        #expect(Color.border.hexString == "E4E0D8")
        #expect(Color.divider.hexString == "F0EDE6")
        #expect(Color.ink.hexString == "2B2A28")
        #expect(Color.inkSoft.hexString == "6B6862")
        #expect(Color.inkMuted.hexString == "8A867E")
        #expect(Color.sage.hexString == "B7CDAE")
        #expect(Color.sageTint.hexString == "E8EFE2")
        #expect(Color.sageText.hexString == "33472C")
        #expect(Color.butter.hexString == "F0D999")
        #expect(Color.butterTint.hexString == "FAF1D6")
        #expect(Color.butterText.hexString == "665012")
        #expect(Color.blush.hexString == "E9AFAB")
        #expect(Color.blushTint.hexString == "F7E3E1")
        #expect(Color.blushText.hexString == "6E2E2A")
        #expect(Color.sky.hexString == "A9C7E0")
        #expect(Color.skyTint.hexString == "E4EEF6")
        #expect(Color.skyText.hexString == "274963")
        #expect(Color.lilac.hexString == "C7BEE0")
        #expect(Color.lilacTint.hexString == "EEEAF6")
        #expect(Color.lilacText.hexString == "453963")
        #expect(Color.clay.hexString == "B24A3F")
    }

    @Test("spacing follows the 4pt rhythm from the token set")
    func spacingRhythm() {
        #expect(Metrics.space1 == 4)
        #expect(Metrics.space2 == 8)
        #expect(Metrics.space3 == 12)
        #expect(Metrics.space4 == 16)
        #expect(Metrics.space5 == 20)
        #expect(Metrics.space6 == 26)
        #expect(Metrics.space7 == 32)
        #expect(Metrics.space8 == 40)
        #expect(Metrics.space9 == 56)
        #expect(Metrics.space10 == 72)
        #expect(Metrics.hitMin == 44)
    }

    @Test("radii match the token set")
    func radii() {
        #expect(Metrics.radiusSwatch == 6)
        #expect(Metrics.radiusKey == 8)
        #expect(Metrics.radiusTile == 10)
        #expect(Metrics.radiusCard == 14)
        #expect(Metrics.radiusPill == 999)
        #expect(Metrics.strokeTile == 2)
        #expect(Metrics.strokeCard == 1)
        #expect(Metrics.contentMaxWidth == 420)
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
