import Testing
import UIKit
@testable import Tables

struct FontRegistrationTests {

    @Test("bundled fonts are registered under their PostScript names",
          arguments: ["ZillaSlab-SemiBold", "LibreFranklin-Regular", "LibreFranklin-SemiBold"])
    func fontIsAvailable(_ name: String) {
        let font = UIFont(name: name, size: 16)
        #expect(font != nil, "Font \(name) is not registered — check UIAppFonts in Info.plist")
        #expect(font?.fontName == name)
    }

    @Test("the multiplication sign renders from the bundled fonts, not a fallback")
    func multiplicationSignIsCovered() {
        for name in ["ZillaSlab-SemiBold", "LibreFranklin-Regular"] {
            let font = try! #require(UIFont(name: name, size: 16))
            let ctFont = font as CTFont
            var glyph: CGGlyph = 0
            var character: UniChar = 0x00D7
            let covered = CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1)
            #expect(covered, "\(name) has no glyph for ×")
        }
    }
}
