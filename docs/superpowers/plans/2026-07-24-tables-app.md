# Tables App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a calm, login-free iOS times-tables practice app with Countdown and Revision modes, multiple-choice and number-pad answering, and a per-fact mastery grid.

**Architecture:** Pure Swift value types hold all game rules (`Model/`), an `@Observable` `GameSession` drives play through an injected clock and RNG so it is fully unit-testable, SwiftData persists per-fact timings and run history behind a `ProgressRecording` protocol, and SwiftUI screens consume a token-based design system mirroring the Claude Design project.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, Swift Testing (units), XCTest (UI), AVAudioEngine, Xcode 26.6.

**Spec:** `docs/superpowers/specs/2026-07-24-tables-app-design.md` — read it before starting.

## Global Constraints

- Deployment target **iOS 26.0**. Devices: iPhone **and** iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
- **Portrait only**, both idioms. **Light appearance only** (`UIUserInterfaceStyle = Light`).
- The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77). **Never edit `project.pbxproj` to add files** — files dropped into `Tables/`, `TablesTests/`, `TablesUITests/` are picked up automatically. Only build *settings* require pbxproj edits.
- Unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). UI tests use **XCTest**.
- Run unit tests with: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet`
- Run everything with: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -quiet`
- Multiplication is always rendered `×` (U+00D7), never `x`.
- **No emoji anywhere** in UI copy. This is a brand rule.
- All copy is sentence case except caps "eyebrow" labels.
- Anything random takes an injected `RandomNumberGenerator`. Anything time-based takes an injected `Date`. No `Date()` or `Task.sleep` inside `Model/` or `Game/`.
- **Actor isolation.** The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the test targets do not. So every type declared in `Tables/` is implicitly `@MainActor`, including its synthesised `Equatable`/`Hashable` conformances — and a nonisolated test comparing two of them warns: *"main actor-isolated conformance of 'X' to 'Equatable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode."*

  Rule: **every pure value type and pure-logic type under `Tables/Model/` and `Tables/Game/` is declared `nonisolated`.** That covers `Fact`, `GameMode`, `AnswerMode`, `GameLength`, `GameConfig`, `FactHistory`, `MasteryLevel`, `Mastery`, `QuestionPicker`, `DistractorGenerator`, `RunRecord`, `ScoreBoardResult`, `ScoreBoard`, `AnyRandomGenerator`, and `TileState` in the design system. It is a truthful statement about types that carry no shared mutable state, not a warning suppression.

  The exceptions stay `@MainActor` as the tasks already specify, because they genuinely touch UI or a `ModelContext`: `ProgressRecording` and both stores, `GameSession`, `AppSettings`, `FeedbackPlaying` and its implementations, `AppRouter`, `SetupModel`. SwiftData `@Model` classes (`FactStat`, `GameRun`) keep the target default.

  Never reach for `@preconcurrency`, `nonisolated(unsafe)`, or a warning flag. **Test output must be pristine — warnings are findings.**
- Every task ends with a commit.

## File Structure

```
Tables/
  TablesApp.swift              App entry, ModelContainer, Route stack
  Info.plist                   Orientation, appearance, UIAppFonts
  DesignSystem/
    Palette.swift              Colour tokens + hex init
    Metrics.swift              Spacing, radii, strokes
    Motion.swift               Durations, easing, Reduce Motion
    Typography.swift           Font tokens
    Components/
      Card.swift  Eyebrow.swift  PillButton.swift  TileButton.swift
      Chip.swift  BackButton.swift  BrandMark.swift
  Model/
    Fact.swift  GameMode.swift  AnswerMode.swift  GameLength.swift
    GameConfig.swift  DistractorGenerator.swift  Mastery.swift
    QuestionPicker.swift  ScoreBoard.swift
    FactStat.swift  GameRun.swift
    ProgressRecording.swift  InMemoryProgressStore.swift  SwiftDataProgressStore.swift
  Game/
    GameSession.swift
  Features/
    Home/HomeView.swift
    Setup/SetupView.swift
    Game/GameView.swift  MultipleChoiceView.swift  NumberPadView.swift
    Results/ResultsView.swift
    Progress/MasteryGridView.swift
    Settings/SettingsView.swift
  Services/
    AppSettings.swift  FeedbackPlayer.swift
  Resources/Fonts/
    ZillaSlab-SemiBold.ttf  LibreFranklin-Regular.ttf  LibreFranklin-SemiBold.ttf
```

---

### Task 1: Project foundation — settings, fonts, clean slate

**Files:**
- Delete: `Tables/Item.swift`, `Tables/ContentView.swift`
- Modify: `Tables/TablesApp.swift`, `Tables/Info.plist`, `Tables.xcodeproj/project.pbxproj`
- Create: `Tables/Resources/Fonts/{ZillaSlab-SemiBold,LibreFranklin-Regular,LibreFranklin-SemiBold}.ttf`
- Create: `Tables/Resources/Fonts/OFL.txt`
- Test: `TablesTests/FontRegistrationTests.swift`
- Delete: `TablesTests/TablesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: three registered font families addressable by the PostScript names `ZillaSlab-SemiBold`, `LibreFranklin-Regular`, `LibreFranklin-SemiBold`. An app that launches to a bare `Color.canvas` screen.

- [ ] **Step 1: Download the three fonts and their licence**

The Libre Franklin statics generated by Google's CDN are broken (PostScript name `LibreFranklinThin-Regular`, 228 glyphs). Use the upstream repo, which yields correct names and 919 glyphs.

```bash
mkdir -p Tables/Resources/Fonts
curl -sL -o Tables/Resources/Fonts/ZillaSlab-SemiBold.ttf \
  "https://github.com/google/fonts/raw/main/ofl/zillaslab/ZillaSlab-SemiBold.ttf"
curl -sL -o Tables/Resources/Fonts/LibreFranklin-Regular.ttf \
  "https://github.com/impallari/Libre-Franklin/raw/master/fonts/TTF/LibreFranklin-Regular.ttf"
curl -sL -o Tables/Resources/Fonts/LibreFranklin-SemiBold.ttf \
  "https://github.com/impallari/Libre-Franklin/raw/master/fonts/TTF/LibreFranklin-SemiBold.ttf"
curl -sL -o Tables/Resources/Fonts/OFL.txt \
  "https://github.com/impallari/Libre-Franklin/raw/master/OFL.txt"
ls -la Tables/Resources/Fonts/
```

Expected: `ZillaSlab-SemiBold.ttf` ≈270KB, both Libre Franklin files ≈142KB, `OFL.txt` present. If any file is under 10KB the download failed — stop and report.

- [ ] **Step 2: Register the fonts and lock orientation/appearance in Info.plist**

Replace the whole of `Tables/Info.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIAppFonts</key>
	<array>
		<string>ZillaSlab-SemiBold.ttf</string>
		<string>LibreFranklin-Regular.ttf</string>
		<string>LibreFranklin-SemiBold.ttf</string>
	</array>
	<key>UIUserInterfaceStyle</key>
	<string>Light</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
	<key>UISupportedInterfaceOrientations~ipad</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationPortraitUpsideDown</string>
	</array>
</dict>
</plist>
```

`UIBackgroundModes: remote-notification` is removed — the app sends no notifications, and shipping an unused background mode invites App Review questions.

- [ ] **Step 3: Lower the deployment target**

```bash
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 26.5;/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/g' Tables.xcodeproj/project.pbxproj
grep -c "IPHONEOS_DEPLOYMENT_TARGET = 26.0;" Tables.xcodeproj/project.pbxproj
```

Expected: a count of 6 or more (Debug + Release for three targets). `TARGETED_DEVICE_FAMILY = "1,2"` is already correct — leave it.

- [ ] **Step 4: Write the failing font-registration test**

Create `TablesTests/FontRegistrationTests.swift`:

```swift
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
```

Delete the template test:

```bash
rm TablesTests/TablesTests.swift
```

- [ ] **Step 5: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL. The fonts exist on disk but `ContentView`/`Item` still reference SwiftData scaffolding, and the fonts are not yet proven to load. If it unexpectedly passes, the synchronized group already picked up the TTFs — that is fine, continue.

- [ ] **Step 6: Replace the app entry point and delete the template**

```bash
rm Tables/Item.swift Tables/ContentView.swift
```

Replace `Tables/TablesApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct TablesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [FactStat.self, GameRun.self])
    }
}

/// Placeholder shell. Task 13 replaces this with the real navigation stack.
struct RootView: View {
    var body: some View {
        Color(red: 0.949, green: 0.937, blue: 0.910)
            .ignoresSafeArea()
    }
}
```

This references `FactStat` and `GameRun`, which do not exist yet. Add a temporary stand-in file `Tables/Model/TemporaryModels.swift` so the project compiles until Task 8 replaces it:

```swift
import Foundation
import SwiftData

// Temporary placeholders so the app compiles before Task 8.
// Task 8 deletes this file and creates FactStat.swift / GameRun.swift.
@Model final class FactStat {
    var key: String = ""
    init(key: String) { self.key = key }
}

@Model final class GameRun {
    var configKey: String = ""
    init(configKey: String) { self.configKey = configKey }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS — 4 test cases (3 parameterised + 1).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Set up project foundation: fonts, orientation, appearance

Bundles Zilla Slab and Libre Franklin, locks the app to portrait and
light appearance, lowers the deployment target to iOS 26.0, and clears
the Xcode template scaffolding."
```

---

### Task 2: Design tokens

**Files:**
- Create: `Tables/DesignSystem/Palette.swift`, `Metrics.swift`, `Motion.swift`, `Typography.swift`
- Test: `TablesTests/DesignTokenTests.swift`

**Interfaces:**
- Consumes: the registered fonts from Task 1.
- Produces:
  - `Color.paper/.canvas/.tileNeutral/.line/.border/.divider/.ink/.inkSoft/.inkMuted`
  - `Color.sage/.sageTint/.sageText` and the same triple for `butter`, `blush`, `sky`, `lilac`; plus `Color.clay`
  - `enum Metrics` with `space1…space10`, `radiusSwatch/Key/Tile/Card`, `strokeTile/strokeCard`, `hitMin`, `contentMaxWidth`
  - `enum Motion` with the raw duration tokens `quick/fade/pop/flip` (`TimeInterval`, mirroring `motion.css`), the derived `fadeAnimation`/`popAnimation` (`Animation`), the shared `easeOut` (`UnitCurve`), and `static func animation(_ base: Animation?, reduceMotion: Bool) -> Animation?`. Later tasks consume `Motion.pop`, `Motion.fadeAnimation`, `Motion.popAnimation` and `Motion.animation(_:reduceMotion:)` — nothing else.
  - `enum Typography` with `static func display(_ size: CGFloat, relativeTo: Font.TextStyle = .body) -> Font` and `static func ui(_ size: CGFloat, weight: UIFontWeight = .regular, relativeTo: Font.TextStyle = .body) -> Font`, plus `enum UIFontWeight { case regular, semibold }` and `static let capsTracking: CGFloat`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/DesignTokenTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — compile errors, `cannot find 'Metrics' in scope`.

- [ ] **Step 3: Create `Tables/DesignSystem/Palette.swift`**

```swift
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
```

- [ ] **Step 4: Create `Tables/DesignSystem/Metrics.swift`**

```swift
import CoreGraphics

/// Layout constants from the design system's spacing and radius tokens.
enum Metrics {
    // 4pt base rhythm.
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 26
    static let space7: CGFloat = 32
    static let space8: CGFloat = 40
    static let space9: CGFloat = 56
    static let space10: CGFloat = 72

    static let radiusSwatch: CGFloat = 6
    static let radiusKey: CGFloat = 8
    static let radiusTile: CGFloat = 10
    static let radiusCard: CGFloat = 14
    static let radiusPill: CGFloat = 999

    static let strokeTile: CGFloat = 2
    static let strokeCard: CGFloat = 1

    static let hitMin: CGFloat = 44

    /// The design is drawn for a phone. On iPad the content column is capped
    /// and centred rather than stretched.
    static let contentMaxWidth: CGFloat = 420
}
```

- [ ] **Step 5: Create `Tables/DesignSystem/Motion.swift`**

```swift
import SwiftUI

/// Restrained motion: a pop on select, a flip on reveal, quiet colour fades
/// everywhere else. Nothing loops or bounces idly.
enum Motion {
    static let quick: TimeInterval = 0.08
    static let fade: TimeInterval = 0.18
    static let pop: TimeInterval = 0.30
    static let flip: TimeInterval = 0.40

    static let easeOut = UnitCurve.bezier(
        startControlPoint: CGPoint(x: 0.22, y: 1),
        endControlPoint: CGPoint(x: 0.36, y: 1)
    )

    static let fadeAnimation = Animation.easeInOut(duration: fade)
    static let popAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: pop)
    static let quickAnimation = Animation.easeOut(duration: quick)

    /// Single place where Reduce Motion is honoured, so no view has to
    /// remember to check it.
    static func animation(_ base: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : base
    }
}
```

- [ ] **Step 6: Create `Tables/DesignSystem/Typography.swift`**

```swift
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
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add design system tokens

Palette, spacing, radii, motion and typography mirrored one-for-one from
the Claude Design project token set, with Reduce Motion handled in a
single place."
```

---

### Task 3: Core value types

**Files:**
- Create: `Tables/Model/Fact.swift`, `GameMode.swift`, `AnswerMode.swift`, `GameLength.swift`, `GameConfig.swift`
- Test: `TablesTests/GameConfigTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct Fact: Hashable, Sendable, Identifiable { let a: Int; let b: Int; var answer: Int; var key: String; var display: String; var revealed: String }` — `revealed` is the full "7 × 8 = 56" form shown after a wrong answer in Revision
  - `enum GameMode: String, CaseIterable, Codable, Sendable { case countdown, revision }` with `var title: String`, `var lowercasedTitle: String`, `var lengthSectionLabel: String`
  - `enum AnswerMode: String, CaseIterable, Codable, Sendable { case multipleChoice, numberPad }` with `var title: String`, `var subtitle: String`
  - `enum GameLength: Hashable, Codable, Sendable { case seconds(Int); case questions(Int); case endless }` with `var key: String`, `var summary: String`, `static let countdownOptions: [GameLength]`, `static let revisionOptions: [GameLength]`
  - `struct GameConfig: Hashable, Sendable` with `mode`, `tables: Set<Int>`, `answerMode`, `length`, and `var configKey: String`, `var tablesSummary: String`, `var facts: [Fact]`, `var isStartable: Bool`, `var summary: String`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/GameConfigTests.swift`:

```swift
import Testing
@testable import Tables

struct FactTests {

    @Test("a fact knows its answer, storage key and display string")
    func factBasics() {
        let fact = Fact(a: 7, b: 8)
        #expect(fact.answer == 56)
        #expect(fact.key == "7x8")
        #expect(fact.display == "7 × 8")
    }

    @Test("the display string uses the multiplication sign, never a letter x")
    func displayUsesMultiplicationSign() {
        #expect(Fact(a: 3, b: 4).display.contains("\u{00D7}"))
        #expect(!Fact(a: 3, b: 4).display.contains("x"))
    }
}

struct GameLengthTests {

    @Test("lengths produce stable keys for score-board scoping")
    func keys() {
        #expect(GameLength.seconds(60).key == "cd60")
        #expect(GameLength.questions(20).key == "rev20")
        #expect(GameLength.endless.key == "revEndless")
    }

    @Test("lengths summarise for the setup screen")
    func summaries() {
        #expect(GameLength.seconds(90).summary == "90 seconds")
        #expect(GameLength.questions(30).summary == "30 questions")
        #expect(GameLength.endless.summary == "Endless")
    }

    @Test("the option lists match the spec")
    func optionLists() {
        #expect(GameLength.countdownOptions == [.seconds(30), .seconds(60), .seconds(90), .seconds(120)])
        #expect(GameLength.revisionOptions == [
            .questions(10), .questions(20), .questions(30),
            .questions(40), .questions(50), .questions(60), .endless
        ])
    }
}

struct GameConfigTests {

    private func config(
        mode: GameMode = .countdown,
        tables: Set<Int> = [3, 6, 7, 8],
        answerMode: AnswerMode = .multipleChoice,
        length: GameLength = .seconds(60)
    ) -> GameConfig {
        GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
    }

    @Test("the config key sorts tables so selection order cannot fork a score board")
    func configKeyIsOrderIndependent() {
        let a = config(tables: [8, 3, 7, 6])
        let b = config(tables: [3, 6, 7, 8])
        #expect(a.configKey == b.configKey)
        #expect(a.configKey == "countdown|3-6-7-8|multipleChoice|cd60")
    }

    @Test("changing any dimension changes the config key")
    func configKeyIsSensitiveToEveryDimension() {
        let base = config().configKey
        #expect(config(mode: .revision, length: .questions(20)).configKey != base)
        #expect(config(tables: [3, 6, 7]).configKey != base)
        #expect(config(answerMode: .numberPad).configKey != base)
        #expect(config(length: .seconds(30)).configKey != base)
    }

    @Test("facts cover every multiplicand 1 through 12 for each selected table")
    func factsCoverTheGrid() {
        let facts = config(tables: [3, 7]).facts
        #expect(facts.count == 24)
        #expect(facts.allSatisfy { [3, 7].contains($0.a) })
        #expect(Set(facts.map(\.b)) == Set(1...12))
    }

    @Test("the tables summary reads as the design specifies")
    func tablesSummary() {
        #expect(config(tables: [7, 3]).tablesSummary == "×3  ×7")
        #expect(config(tables: Set(1...12)).tablesSummary == "All tables")
        #expect(config(tables: []).tablesSummary == "None chosen")
    }

    @Test("a config with no tables cannot start")
    func startability() {
        #expect(config().isStartable)
        #expect(!config(tables: []).isStartable)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'Fact' in scope`.

- [ ] **Step 3: Create `Tables/Model/Fact.swift`**

```swift
import Foundation

/// One multiplication fact. `a` is the table, `b` the multiplicand.
struct Fact: Hashable, Sendable, Identifiable {
    let a: Int
    let b: Int

    var id: String { key }
    var answer: Int { a * b }

    /// Stable storage key, e.g. "7x8".
    var key: String { "\(a)x\(b)" }

    /// Uses U+00D7, never a lowercase letter x.
    var display: String { "\(a) \u{00D7} \(b)" }

    /// The fully revealed fact, shown after a wrong answer in Revision.
    var revealed: String { "\(display) = \(answer)" }
}
```

- [ ] **Step 4: Create `Tables/Model/GameMode.swift`**

```swift
import Foundation

enum GameMode: String, CaseIterable, Codable, Sendable {
    case countdown
    case revision

    var title: String {
        switch self {
        case .countdown: "Countdown"
        case .revision: "Revision"
        }
    }

    var lowercasedTitle: String { title.lowercased() }

    /// The setup screen labels the third section differently per mode.
    var lengthSectionLabel: String {
        switch self {
        case .countdown: "Time limit"
        case .revision: "Length"
        }
    }
}
```

- [ ] **Step 5: Create `Tables/Model/AnswerMode.swift`**

```swift
import Foundation

enum AnswerMode: String, CaseIterable, Codable, Sendable {
    case multipleChoice
    case numberPad

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .numberPad: "Number pad"
        }
    }

    var subtitle: String {
        switch self {
        case .multipleChoice: "Pick from the tiles"
        case .numberPad: "Type the answer"
        }
    }
}
```

Voice is deliberately absent from this enum. It is a static, disabled row in the setup screen, not a selectable case — modelling it as a case would mean handling an unreachable state everywhere.

- [ ] **Step 6: Create `Tables/Model/GameLength.swift`**

```swift
import Foundation

enum GameLength: Hashable, Codable, Sendable {
    case seconds(Int)
    case questions(Int)
    case endless

    static let countdownOptions: [GameLength] = [
        .seconds(30), .seconds(60), .seconds(90), .seconds(120)
    ]

    static let revisionOptions: [GameLength] = [
        .questions(10), .questions(20), .questions(30),
        .questions(40), .questions(50), .questions(60), .endless
    ]

    /// Stable component of the score-board config key.
    var key: String {
        switch self {
        case .seconds(let value): "cd\(value)"
        case .questions(let value): "rev\(value)"
        case .endless: "revEndless"
        }
    }

    /// Full sentence for the setup screen's collapsed summary.
    var summary: String {
        switch self {
        case .seconds(let value): "\(value) seconds"
        case .questions(let value): "\(value) questions"
        case .endless: "Endless"
        }
    }

    /// Short form for the chip itself.
    var chipLabel: String {
        switch self {
        case .seconds(let value): "\(value)s"
        case .questions(let value): "\(value)"
        case .endless: "Endless"
        }
    }

    /// Compact form for the results eyebrow.
    var shortSummary: String {
        switch self {
        case .seconds(let value): "\(value) sec"
        case .questions(let value): "\(value) questions"
        case .endless: "endless"
        }
    }
}
```

- [ ] **Step 7: Create `Tables/Model/GameConfig.swift`**

```swift
import Foundation

/// Everything the player chose on the setup screen. Scores are scoped to this
/// whole shape, so only like-for-like runs are ever compared.
struct GameConfig: Hashable, Sendable {
    var mode: GameMode
    var tables: Set<Int>
    var answerMode: AnswerMode
    var length: GameLength

    static let allTables = Set(1...12)
    static let multiplicands = 1...12

    var sortedTables: [Int] { tables.sorted() }

    var configKey: String {
        let tableList = sortedTables.map(String.init).joined(separator: "-")
        return "\(mode.rawValue)|\(tableList)|\(answerMode.rawValue)|\(length.key)"
    }

    var facts: [Fact] {
        sortedTables.flatMap { a in
            Self.multiplicands.map { Fact(a: a, b: $0) }
        }
    }

    var isStartable: Bool { !tables.isEmpty }

    var tablesSummary: String {
        if tables.isEmpty { return "None chosen" }
        if tables == Self.allTables { return "All tables" }
        return sortedTables.map { "\u{00D7}\($0)" }.joined(separator: "  ")
    }

    /// Single-space variant used in the results eyebrow.
    var compactTablesSummary: String {
        if tables == Self.allTables { return "all tables" }
        return sortedTables.map { "\u{00D7}\($0)" }.joined(separator: " ")
    }

    /// e.g. "Countdown · 60 sec · ×3 ×6 ×7 ×8"
    var summary: String {
        "\(mode.title) \u{00B7} \(length.shortSummary) \u{00B7} \(compactTablesSummary)"
    }

    static let `default` = GameConfig(
        mode: .countdown,
        tables: [3, 6, 7, 8],
        answerMode: .multipleChoice,
        length: .seconds(60)
    )
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add core game value types

Fact, GameMode, AnswerMode, GameLength and GameConfig, with the config
key that scopes score boards to an exact configuration."
```

---

### Task 4: Distractor generator

**Files:**
- Create: `Tables/Model/DistractorGenerator.swift`
- Test: `TablesTests/DistractorGeneratorTests.swift`

**Interfaces:**
- Consumes: `Fact` (Task 3).
- Produces: `enum DistractorGenerator` with
  `static func options(for fact: Fact, count: Int, using rng: inout some RandomNumberGenerator) -> [Int]`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/DistractorGeneratorTests.swift`:

```swift
import Testing
@testable import Tables

/// Deterministic generator so option sets are reproducible in tests.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

struct DistractorGeneratorTests {

    @Test("returns exactly the requested number of options", arguments: [4, 6])
    func returnsRequestedCount(_ count: Int) {
        var rng = SeededRandom(seed: 42)
        for a in 1...12 {
            for b in 1...12 {
                let options = DistractorGenerator.options(
                    for: Fact(a: a, b: b), count: count, using: &rng
                )
                #expect(options.count == count, "\(a)×\(b) produced \(options.count) options")
            }
        }
    }

    @Test("always includes the correct answer", arguments: [4, 6])
    func alwaysIncludesTheAnswer(_ count: Int) {
        var rng = SeededRandom(seed: 7)
        for a in 1...12 {
            for b in 1...12 {
                let fact = Fact(a: a, b: b)
                let options = DistractorGenerator.options(for: fact, count: count, using: &rng)
                #expect(options.contains(fact.answer), "\(fact.key) omitted its own answer")
            }
        }
    }

    @Test("all options are unique and positive")
    func optionsAreUniqueAndPositive() {
        var rng = SeededRandom(seed: 99)
        for a in 1...12 {
            for b in 1...12 {
                let options = DistractorGenerator.options(
                    for: Fact(a: a, b: b), count: 6, using: &rng
                )
                #expect(Set(options).count == options.count, "\(a)×\(b) had duplicates: \(options)")
                #expect(options.allSatisfy { $0 > 0 }, "\(a)×\(b) had non-positive: \(options)")
            }
        }
    }

    @Test("copes with the smallest fact, where few smaller distractors exist")
    func handlesSmallestFact() {
        var rng = SeededRandom(seed: 1)
        let options = DistractorGenerator.options(for: Fact(a: 1, b: 1), count: 6, using: &rng)
        #expect(options.count == 6)
        #expect(options.contains(1))
        #expect(Set(options).count == 6)
        #expect(options.allSatisfy { $0 > 0 })
    }

    @Test("copes with the largest fact")
    func handlesLargestFact() {
        var rng = SeededRandom(seed: 2)
        let options = DistractorGenerator.options(for: Fact(a: 12, b: 12), count: 6, using: &rng)
        #expect(options.count == 6)
        #expect(options.contains(144))
    }

    @Test("does not always place the answer in the same slot")
    func answerPositionVaries() {
        var indices = Set<Int>()
        for seed in UInt64(1)...UInt64(40) {
            var rng = SeededRandom(seed: seed)
            let fact = Fact(a: 7, b: 8)
            let options = DistractorGenerator.options(for: fact, count: 6, using: &rng)
            indices.insert(options.firstIndex(of: fact.answer)!)
        }
        #expect(indices.count > 1, "the answer always landed in the same position")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'DistractorGenerator' in scope`.

- [ ] **Step 3: Create `Tables/Model/DistractorGenerator.swift`**

```swift
import Foundation

/// Builds the option set for multiple choice.
///
/// Distractors are drawn from two families of realistic mistake: an off-by-a-few
/// slip, and a neighbouring multiple of the same table. A random spread of
/// unrelated numbers would be trivially dismissable and teach nothing.
enum DistractorGenerator {

    /// Bounded so a fact with few plausible neighbours cannot spin forever.
    private static let maxAttempts = 80

    static func options(
        for fact: Fact,
        count: Int,
        using rng: inout some RandomNumberGenerator
    ) -> [Int] {
        let answer = fact.answer
        var values: Set<Int> = [answer]

        var attempts = 0
        while values.count < count && attempts < maxAttempts {
            attempts += 1
            let drift = Int.random(in: 0...6, using: &rng) - 3
            let step = Bool.random(using: &rng) ? 1 : fact.a
            let candidate = answer + drift * step
            if candidate > 0 && candidate != answer {
                values.insert(candidate)
            }
        }

        // Small answers can exhaust the plausible neighbours; pad upward so the
        // grid is never short.
        var padding = 1
        while values.count < count {
            values.insert(answer + padding)
            padding += 1
        }

        return values.shuffled(using: &rng)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add multiple-choice distractor generator

Draws distractors from off-by-a-few slips and neighbouring multiples of
the same table, so wrong options are plausible rather than dismissable."
```

---

### Task 5: Mastery rules and fact history

**Files:**
- Create: `Tables/Model/Mastery.swift`
- Test: `TablesTests/MasteryTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct FactHistory: Hashable, Sendable { var attempts: Int; var correctCount: Int; var averageMillis: Double }` with `static let unseen: FactHistory`
  - `enum MasteryLevel: Hashable, Sendable, CaseIterable { case notYet, gettingThere, mastered }` with `var legendLabel: String`
  - `enum Mastery` with `static let requiredCorrectCount: Int`, `static let masteryThresholdMillis: Double`, `static func level(for history: FactHistory) -> MasteryLevel`, `static let emaAlpha: Double`, `static func updatedAverage(current: Double, correctCount: Int, latestMillis: Double) -> Double`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/MasteryTests.swift`:

```swift
import Testing
@testable import Tables

struct MasteryTests {

    @Test("a fact never attempted is Not yet")
    func unseenIsNotYet() {
        #expect(Mastery.level(for: .unseen) == .notYet)
        #expect(Mastery.level(for: FactHistory(attempts: 0, correctCount: 0, averageMillis: 0)) == .notYet)
    }

    @Test("three fast correct answers earn Mastered")
    func threeFastCorrectIsMastered() {
        let history = FactHistory(attempts: 3, correctCount: 3, averageMillis: 2999)
        #expect(Mastery.level(for: history) == .mastered)
    }

    @Test("two fast correct answers is not yet Mastered")
    func twoCorrectIsNotEnough() {
        let history = FactHistory(attempts: 2, correctCount: 2, averageMillis: 1200)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("three correct but slow is Getting there")
    func slowIsNotMastered() {
        let history = FactHistory(attempts: 3, correctCount: 3, averageMillis: 3000)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("attempted but never correct is Getting there, not Not yet")
    func attemptedButWrongIsGettingThere() {
        let history = FactHistory(attempts: 5, correctCount: 0, averageMillis: 0)
        #expect(Mastery.level(for: history) == .gettingThere)
    }

    @Test("the first correct answer sets the average outright")
    func firstCorrectSeedsTheAverage() {
        let updated = Mastery.updatedAverage(current: 0, correctCount: 0, latestMillis: 2400)
        #expect(updated == 2400)
    }

    @Test("later answers blend in at alpha 0.3, so the average tracks improvement")
    func laterAnswersBlend() {
        let updated = Mastery.updatedAverage(current: 4000, correctCount: 1, latestMillis: 2000)
        #expect(abs(updated - 3400) < 0.0001)
    }

    @Test("a run of fast answers pulls a slow average below the mastery bar")
    func improvementIsReflected() {
        var average = 6000.0
        for index in 0..<8 {
            average = Mastery.updatedAverage(current: average, correctCount: index + 1, latestMillis: 1500)
        }
        #expect(average < Mastery.masteryThresholdMillis)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'Mastery' in scope`.

- [ ] **Step 3: Create `Tables/Model/Mastery.swift`**

```swift
import Foundation

/// A plain snapshot of one fact's answering history, free of SwiftData so the
/// rules below can be tested as values.
struct FactHistory: Hashable, Sendable {
    var attempts: Int
    var correctCount: Int
    var averageMillis: Double

    static let unseen = FactHistory(attempts: 0, correctCount: 0, averageMillis: 0)

    var isUnseen: Bool { attempts == 0 }
}

enum MasteryLevel: Hashable, Sendable, CaseIterable {
    case notYet
    case gettingThere
    case mastered

    var legendLabel: String {
        switch self {
        case .notYet: "Not yet"
        case .gettingThere: "Getting there"
        case .mastered: "Mastered"
        }
    }
}

enum Mastery {
    /// One lucky fast answer should not read as mastery.
    static let requiredCorrectCount = 3
    static let masteryThresholdMillis: Double = 3000

    /// Exponential moving average, so the figure tracks current ability rather
    /// than staying anchored by early fumbling.
    static let emaAlpha = 0.3

    static func level(for history: FactHistory) -> MasteryLevel {
        guard history.attempts > 0 else { return .notYet }
        if history.correctCount >= requiredCorrectCount
            && history.averageMillis < masteryThresholdMillis {
            return .mastered
        }
        return .gettingThere
    }

    /// `correctCount` is the count *before* this answer is folded in.
    static func updatedAverage(
        current: Double,
        correctCount: Int,
        latestMillis: Double
    ) -> Double {
        guard correctCount > 0 else { return latestMillis }
        return emaAlpha * latestMillis + (1 - emaAlpha) * current
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add mastery rules and fact history

Three correct answers under three seconds earns Mastered, with an
exponential moving average so improvement actually shows."
```

---

### Task 6: Question picker

**Files:**
- Create: `Tables/Model/QuestionPicker.swift`
- Test: `TablesTests/QuestionPickerTests.swift`

**Interfaces:**
- Consumes: `Fact`, `GameMode` (Task 3), `FactHistory` (Task 5).
- Produces: `struct QuestionPicker: Sendable` with `init(facts: [Fact], mode: GameMode)` and
  `func next(history: [String: FactHistory], previous: Fact?, using rng: inout some RandomNumberGenerator) -> Fact`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/QuestionPickerTests.swift`:

```swift
import Testing
@testable import Tables

struct QuestionPickerTests {

    private let threeAndSeven = GameConfig(
        mode: .revision, tables: [3, 7], answerMode: .numberPad, length: .questions(10)
    ).facts

    @Test("never repeats the previous fact when others are available")
    func neverRepeatsConsecutively() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .countdown)
        var rng = SeededRandom(seed: 5)
        var previous: Fact? = nil
        for _ in 0..<200 {
            let next = picker.next(history: [:], previous: previous, using: &rng)
            #expect(next != previous)
            previous = next
        }
    }

    @Test("a single-fact pool returns that fact rather than deadlocking")
    func singleFactPool() {
        let only = Fact(a: 1, b: 1)
        let picker = QuestionPicker(facts: [only], mode: .revision)
        var rng = SeededRandom(seed: 3)
        #expect(picker.next(history: [:], previous: only, using: &rng) == only)
    }

    @Test("Revision serves every unseen fact before repeating any of them")
    func revisionExhaustsUnseenFirst() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .revision)
        var rng = SeededRandom(seed: 11)
        var history: [String: FactHistory] = [:]
        var served: [Fact] = []
        var previous: Fact? = nil

        for _ in 0..<threeAndSeven.count {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            served.append(fact)
            history[fact.key] = FactHistory(attempts: 1, correctCount: 1, averageMillis: 1500)
            previous = fact
        }

        #expect(Set(served) == Set(threeAndSeven), "some facts were never served")
        #expect(served.count == Set(served).count, "a fact repeated before coverage completed")
    }

    @Test("Revision favours slow facts once everything has been seen")
    func revisionWeightsSlowFacts() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .revision)
        let slow = Fact(a: 7, b: 8)
        var history: [String: FactHistory] = [:]
        for fact in threeAndSeven {
            let millis = fact == slow ? 9000.0 : 700.0
            history[fact.key] = FactHistory(attempts: 4, correctCount: 4, averageMillis: millis)
        }

        var rng = SeededRandom(seed: 21)
        var slowCount = 0
        var previous: Fact? = nil
        let draws = 3000
        for _ in 0..<draws {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            if fact == slow { slowCount += 1 }
            previous = fact
        }

        // 9000 against 23 facts at 700 gives roughly 36% of the total weight.
        let share = Double(slowCount) / Double(draws)
        #expect(share > 0.20, "slow fact was served only \(share) of the time")
        #expect(share < 0.55)
    }

    @Test("Countdown ignores history and stays close to uniform")
    func countdownIsUniform() {
        let picker = QuestionPicker(facts: threeAndSeven, mode: .countdown)
        let slow = Fact(a: 7, b: 8)
        var history: [String: FactHistory] = [:]
        for fact in threeAndSeven {
            let millis = fact == slow ? 9000.0 : 700.0
            history[fact.key] = FactHistory(attempts: 4, correctCount: 4, averageMillis: millis)
        }

        var rng = SeededRandom(seed: 33)
        var slowCount = 0
        var previous: Fact? = nil
        let draws = 3000
        for _ in 0..<draws {
            let fact = picker.next(history: history, previous: previous, using: &rng)
            if fact == slow { slowCount += 1 }
            previous = fact
        }

        // Uniform over 24 facts is about 4.2%.
        let share = Double(slowCount) / Double(draws)
        #expect(share > 0.02 && share < 0.08, "countdown was not uniform: \(share)")
    }

    @Test("a floor stops very fast facts from being starved entirely")
    func weightFloorApplies() {
        let picker = QuestionPicker(facts: [Fact(a: 2, b: 2), Fact(a: 2, b: 3)], mode: .revision)
        var history: [String: FactHistory] = [:]
        history["2x2"] = FactHistory(attempts: 9, correctCount: 9, averageMillis: 1)
        history["2x3"] = FactHistory(attempts: 9, correctCount: 9, averageMillis: 400)

        var rng = SeededRandom(seed: 44)
        var fastCount = 0
        for _ in 0..<600 {
            // No previous, so both remain eligible on every draw.
            if picker.next(history: history, previous: nil, using: &rng) == Fact(a: 2, b: 2) {
                fastCount += 1
            }
        }
        #expect(fastCount > 200, "the 400ms floor was not applied")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'QuestionPicker' in scope`.

- [ ] **Step 3: Create `Tables/Model/QuestionPicker.swift`**

```swift
import Foundation

/// Chooses the next fact to ask.
///
/// Countdown is uniform — it is a speed test, not a teaching tool. Revision
/// serves every unseen fact first so a session cannot skip a whole table, then
/// weights by how long each fact has been taking.
struct QuestionPicker: Sendable {
    let facts: [Fact]
    let mode: GameMode

    /// Even a fact answered instantly should still come round occasionally.
    static let minimumWeight: Double = 400

    init(facts: [Fact], mode: GameMode) {
        self.facts = facts
        self.mode = mode
    }

    func next(
        history: [String: FactHistory],
        previous: Fact?,
        using rng: inout some RandomNumberGenerator
    ) -> Fact {
        let eligible = facts.count > 1 ? facts.filter { $0 != previous } : facts
        guard !eligible.isEmpty else { return facts[0] }

        switch mode {
        case .countdown:
            return eligible.randomElement(using: &rng) ?? eligible[0]

        case .revision:
            let unseen = eligible.filter { (history[$0.key] ?? .unseen).isUnseen }
            if !unseen.isEmpty {
                return unseen.randomElement(using: &rng) ?? unseen[0]
            }
            return weightedPick(from: eligible, history: history, using: &rng)
        }
    }

    private func weightedPick(
        from candidates: [Fact],
        history: [String: FactHistory],
        using rng: inout some RandomNumberGenerator
    ) -> Fact {
        let weights = candidates.map { fact in
            max(Self.minimumWeight, (history[fact.key] ?? .unseen).averageMillis)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return candidates[0] }

        var target = Double.random(in: 0..<total, using: &rng)
        for (fact, weight) in zip(candidates, weights) {
            target -= weight
            if target <= 0 { return fact }
        }
        return candidates[candidates.count - 1]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add question picker

Countdown draws uniformly; Revision covers every unseen fact first, then
weights by average answer time so slow facts come round more often."
```

---

### Task 7: Score board

**Files:**
- Create: `Tables/Model/ScoreBoard.swift`
- Test: `TablesTests/ScoreBoardTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct RunRecord: Hashable, Sendable, Identifiable { let score: Int; let answered: Int; let date: Date }`
  - `struct ScoreBoardResult: Sendable { let topRuns: [RunRecord]; let isNewBest: Bool; let previousBest: Int?; let bannerText: String }`
  - `enum ScoreBoard` with `static let maximumListed: Int` and
    `static func evaluate(previousRuns: [RunRecord], current: RunRecord) -> ScoreBoardResult`
  - `static func relativeDateLabel(for date: Date, isCurrentRun: Bool, now: Date) -> String`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/ScoreBoardTests.swift`:

```swift
import Testing
import Foundation
@testable import Tables

struct ScoreBoardTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func run(_ score: Int, daysAgo: Double = 0) -> RunRecord {
        RunRecord(score: score, answered: score, date: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("a first run scoring zero is not a personal best")
    func firstRunScoringZero() {
        let result = ScoreBoard.evaluate(previousRuns: [], current: run(0))
        #expect(!result.isNewBest)
        #expect(result.previousBest == nil)
        #expect(result.bannerText == "Your first run \u{2014} every one counts")
    }

    @Test("a first run scoring above zero is a personal best")
    func firstScoringRun() {
        let result = ScoreBoard.evaluate(previousRuns: [], current: run(7))
        #expect(result.isNewBest)
        #expect(result.previousBest == nil)
        #expect(result.bannerText == "New personal best")
    }

    @Test("beating the previous best names the number beaten")
    func beatingPreviousBest() {
        let result = ScoreBoard.evaluate(previousRuns: [run(9, daysAgo: 2), run(4, daysAgo: 3)], current: run(12))
        #expect(result.isNewBest)
        #expect(result.previousBest == 9)
        #expect(result.bannerText == "New personal best \u{2014} beat 9")
    }

    @Test("equalling the previous best is not a new best")
    func equallingIsNotBest() {
        let result = ScoreBoard.evaluate(previousRuns: [run(9, daysAgo: 1)], current: run(9))
        #expect(!result.isNewBest)
        #expect(result.bannerText == "Your best is 9")
    }

    @Test("falling short reports the standing best")
    func fallingShort() {
        let result = ScoreBoard.evaluate(previousRuns: [run(15, daysAgo: 1)], current: run(6))
        #expect(!result.isNewBest)
        #expect(result.bannerText == "Your best is 15")
    }

    @Test("lists at most five runs, highest score first")
    func listsTopFive() {
        let previous = [run(3, daysAgo: 1), run(11, daysAgo: 2), run(8, daysAgo: 3),
                        run(5, daysAgo: 4), run(14, daysAgo: 5), run(1, daysAgo: 6)]
        let result = ScoreBoard.evaluate(previousRuns: previous, current: run(9))
        #expect(result.topRuns.count == 5)
        #expect(result.topRuns.map(\.score) == [14, 11, 9, 8, 5])
    }

    @Test("ties are broken by the earlier run, so a record keeps its place")
    func tiesFavourTheEarlierRun() {
        let older = run(10, daysAgo: 4)
        let current = run(10)
        let result = ScoreBoard.evaluate(previousRuns: [older], current: current)
        #expect(result.topRuns.first == older)
        #expect(result.topRuns.count == 2)
    }

    @Test("the current run is always included in the list")
    func currentRunAlwaysListed() {
        let previous = (1...10).map { run(50 + $0, daysAgo: Double($0)) }
        let result = ScoreBoard.evaluate(previousRuns: previous, current: run(1))
        #expect(result.topRuns.count == ScoreBoard.maximumListed)
        // A low score does not force its way in; the board stays honest.
        #expect(!result.topRuns.contains(run(1)))
    }

    @Test("relative date labels read plainly")
    func dateLabels() {
        #expect(ScoreBoard.relativeDateLabel(for: now, isCurrentRun: true, now: now) == "Just now")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-3600), isCurrentRun: false, now: now) == "Earlier today")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-86_400), isCurrentRun: false, now: now) == "Yesterday")
        #expect(ScoreBoard.relativeDateLabel(for: now.addingTimeInterval(-5 * 86_400), isCurrentRun: false, now: now) == "5 days ago")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'ScoreBoard' in scope`.

- [ ] **Step 3: Create `Tables/Model/ScoreBoard.swift`**

```swift
import Foundation

struct RunRecord: Hashable, Sendable, Identifiable {
    let score: Int
    let answered: Int
    let date: Date

    var id: Date { date }
}

struct ScoreBoardResult: Sendable {
    let topRuns: [RunRecord]
    let isNewBest: Bool
    /// nil when this is the first run for the configuration.
    let previousBest: Int?
    let bannerText: String
    /// The run just played. The results screen highlights this row, and
    /// identity by value is safer than guessing "the newest date".
    let current: RunRecord
}

/// Best runs are scoped to an exact configuration, so only like-for-like runs
/// are ever compared.
enum ScoreBoard {
    static let maximumListed = 5

    static func evaluate(previousRuns: [RunRecord], current: RunRecord) -> ScoreBoardResult {
        let previousBest = previousRuns.map(\.score).max()
        let isNewBest = if let previousBest {
            current.score > previousBest
        } else {
            current.score > 0
        }

        let topRuns = (previousRuns + [current])
            .sorted { left, right in
                left.score == right.score ? left.date < right.date : left.score > right.score
            }
            .prefix(maximumListed)

        return ScoreBoardResult(
            topRuns: Array(topRuns),
            isNewBest: isNewBest,
            previousBest: previousBest,
            bannerText: bannerText(previousBest: previousBest, isNewBest: isNewBest),
            current: current
        )
    }

    private static func bannerText(previousBest: Int?, isNewBest: Bool) -> String {
        guard let previousBest else {
            return isNewBest ? "New personal best" : "Your first run \u{2014} every one counts"
        }
        return isNewBest
            ? "New personal best \u{2014} beat \(previousBest)"
            : "Your best is \(previousBest)"
    }

    static func relativeDateLabel(for date: Date, isCurrentRun: Bool, now: Date) -> String {
        if isCurrentRun { return "Just now" }
        let days = Int(now.timeIntervalSince(date) / 86_400)
        switch days {
        case ..<1: return "Earlier today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add score board

Top five runs per configuration with tie-breaking by earlier date, and
banner copy that handles a first run scoring zero."
```

---

### Task 8: SwiftData models

**Files:**
- Create: `Tables/Model/FactStat.swift`, `Tables/Model/GameRun.swift`
- Delete: `Tables/Model/TemporaryModels.swift`
- Test: `TablesTests/FactStatTests.swift`

**Interfaces:**
- Consumes: `Fact` (Task 3), `FactHistory`, `Mastery` (Task 5).
- Produces:
  - `@Model final class FactStat` with `key`, `a`, `b`, `attempts`, `correctCount`, `averageMillis`, `lastAnsweredAt`; `init(fact: Fact)`; `var history: FactHistory`; `var fact: Fact`; `func recordCorrect(millis: Double?, at date: Date)`; `func recordIncorrect(at date: Date)`
  - `@Model final class GameRun` with `configKey`, `score`, `answered`, `date`; `init(configKey:score:answered:date:)`; `var record: RunRecord`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/FactStatTests.swift`:

```swift
import Testing
import Foundation
@testable import Tables

struct FactStatTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("a new stat starts unseen")
    func newStatIsUnseen() {
        let stat = FactStat(fact: Fact(a: 7, b: 8))
        #expect(stat.key == "7x8")
        #expect(stat.a == 7)
        #expect(stat.b == 8)
        #expect(stat.history == .unseen)
        #expect(Mastery.level(for: stat.history) == .notYet)
    }

    @Test("the first correct answer seeds the average outright")
    func firstCorrectSeedsAverage() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 2200, at: start)
        #expect(stat.attempts == 1)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 2200)
        #expect(stat.lastAnsweredAt == start)
    }

    @Test("later correct answers blend into the moving average")
    func laterCorrectBlends() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 4000, at: start)
        stat.recordCorrect(millis: 2000, at: start)
        #expect(abs(stat.averageMillis - 3400) < 0.0001)
        #expect(stat.correctCount == 2)
    }

    @Test("a correct answer with no timing still counts but leaves the average alone")
    func untimedCorrectLeavesAverageAlone() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 2000, at: start)
        stat.recordCorrect(millis: nil, at: start)
        #expect(stat.attempts == 2)
        #expect(stat.correctCount == 2)
        #expect(stat.averageMillis == 2000)
    }

    @Test("an untimed first correct answer does not fabricate an average")
    func untimedFirstCorrectStaysZero() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: nil, at: start)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 0)
        // No timing means no evidence of speed, so this must not read as mastery.
        stat.recordCorrect(millis: nil, at: start)
        stat.recordCorrect(millis: nil, at: start)
        #expect(Mastery.level(for: stat.history) == .gettingThere)
    }

    @Test("a wrong answer counts as an attempt but never touches the average")
    func wrongAnswerLeavesAverageAlone() {
        let stat = FactStat(fact: Fact(a: 3, b: 4))
        stat.recordCorrect(millis: 1500, at: start)
        stat.recordIncorrect(at: start.addingTimeInterval(60))
        #expect(stat.attempts == 2)
        #expect(stat.correctCount == 1)
        #expect(stat.averageMillis == 1500)
        #expect(stat.lastAnsweredAt == start.addingTimeInterval(60))
    }

    @Test("three fast correct answers reach Mastered through the model")
    func masteryThroughTheModel() {
        let stat = FactStat(fact: Fact(a: 5, b: 5))
        for _ in 0..<3 { stat.recordCorrect(millis: 1400, at: start) }
        #expect(Mastery.level(for: stat.history) == .mastered)
    }

    @Test("a run converts to a plain record")
    func runConvertsToRecord() {
        let run = GameRun(configKey: "countdown|3|numberPad|cd60", score: 11, answered: 14, date: start)
        #expect(run.record == RunRecord(score: 11, answered: 14, date: start))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `FactStat` has no `init(fact:)` (the temporary placeholder from Task 1 takes a `key`).

- [ ] **Step 3: Replace the placeholder models**

```bash
rm Tables/Model/TemporaryModels.swift
```

Create `Tables/Model/FactStat.swift`:

```swift
import Foundation
import SwiftData

/// Answering history for one multiplication fact.
///
/// `averageMillis` is an exponential moving average over *correct* answers
/// only, so it reflects how quickly the child can produce the fact now rather
/// than how long they took the first time they met it.
@Model
final class FactStat {
    @Attribute(.unique) var key: String = ""
    var a: Int = 0
    var b: Int = 0
    var attempts: Int = 0
    var correctCount: Int = 0
    var averageMillis: Double = 0
    var lastAnsweredAt: Date = Date(timeIntervalSince1970: 0)

    init(fact: Fact) {
        self.key = fact.key
        self.a = fact.a
        self.b = fact.b
        self.attempts = 0
        self.correctCount = 0
        self.averageMillis = 0
        self.lastAnsweredAt = Date(timeIntervalSince1970: 0)
    }

    var fact: Fact { Fact(a: a, b: b) }

    var history: FactHistory {
        FactHistory(attempts: attempts, correctCount: correctCount, averageMillis: averageMillis)
    }

    /// `millis` is nil when the answer was correct but the timing is not
    /// trustworthy — a Countdown retry after a wrong first attempt.
    func recordCorrect(millis: Double?, at date: Date) {
        if let millis {
            averageMillis = Mastery.updatedAverage(
                current: averageMillis,
                correctCount: timedCorrectCount,
                latestMillis: millis
            )
            timedCorrectCount += 1
        }
        attempts += 1
        correctCount += 1
        lastAnsweredAt = date
    }

    func recordIncorrect(at date: Date) {
        attempts += 1
        lastAnsweredAt = date
    }

    /// Correct answers that carried a usable timing. Kept separate from
    /// `correctCount` so untimed answers cannot skew the moving average.
    private var timedCorrectCount: Int = 0
}
```

Note the `history` used for mastery reads `correctCount`, but `averageMillis` stays 0 until a timed answer arrives. `Mastery.level` requires `averageMillis < 3000`, and 0 satisfies that — so guard it. Amend `history`:

```swift
    var history: FactHistory {
        FactHistory(
            attempts: attempts,
            // Untimed correct answers prove the child knew it, not that they
            // were quick. Mastery needs timed evidence.
            correctCount: timedCorrectCount,
            averageMillis: averageMillis
        )
    }
```

Create `Tables/Model/GameRun.swift`:

```swift
import Foundation
import SwiftData

/// One completed game, scoped to the exact configuration it was played under.
@Model
final class GameRun {
    var configKey: String = ""
    var score: Int = 0
    var answered: Int = 0
    var date: Date = Date(timeIntervalSince1970: 0)

    init(configKey: String, score: Int, answered: Int, date: Date) {
        self.configKey = configKey
        self.score = score
        self.answered = answered
        self.date = date
    }

    var record: RunRecord {
        RunRecord(score: score, answered: answered, date: date)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS. If `untimedFirstCorrectStaysZero` fails, the `history` amendment in Step 3 was not applied.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add SwiftData models for fact stats and runs

FactStat keeps a moving average over timed correct answers only, so a
Countdown retry cannot make a fact look mastered."
```

---

### Task 9: Progress store

**Files:**
- Create: `Tables/Model/ProgressRecording.swift`, `InMemoryProgressStore.swift`, `SwiftDataProgressStore.swift`
- Test: `TablesTests/ProgressStoreTests.swift`

**Interfaces:**
- Consumes: `Fact`, `FactHistory`, `MasteryLevel`, `FactStat`, `GameRun`, `RunRecord`.
- Produces:
  - `@MainActor protocol ProgressRecording: AnyObject` with
    `func history() -> [String: FactHistory]`,
    `func recordCorrect(_ fact: Fact, millis: Double?, at date: Date)`,
    `func recordIncorrect(_ fact: Fact, at date: Date)`,
    `func recordRun(configKey: String, score: Int, answered: Int, at date: Date)`,
    `func runs(forConfigKey key: String) -> [RunRecord]`
  - a default extension `func masteryLevels() -> [String: MasteryLevel]`
  - `@MainActor final class InMemoryProgressStore: ProgressRecording`
  - `@MainActor final class SwiftDataProgressStore: ProgressRecording` with `init(context: ModelContext)`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/ProgressStoreTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Tables

@MainActor
struct ProgressStoreTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSwiftDataStore() throws -> SwiftDataProgressStore {
        let container = try ModelContainer(
            for: FactStat.self, GameRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return SwiftDataProgressStore(context: ModelContext(container))
    }

    private func stores() throws -> [(String, any ProgressRecording)] {
        [("in-memory", InMemoryProgressStore()), ("SwiftData", try makeSwiftDataStore())]
    }

    @Test("an empty store reports no history")
    func emptyStore() throws {
        for (name, store) in try stores() {
            #expect(store.history().isEmpty, "\(name) was not empty")
            #expect(store.runs(forConfigKey: "anything").isEmpty, "\(name) had runs")
        }
    }

    @Test("recording a correct answer creates and updates history")
    func recordsCorrect() throws {
        for (name, store) in try stores() {
            let fact = Fact(a: 7, b: 8)
            store.recordCorrect(fact, millis: 2000, at: start)
            store.recordCorrect(fact, millis: 2000, at: start)

            let history = try #require(store.history()["7x8"], "\(name) lost the fact")
            #expect(history.attempts == 2, "\(name)")
            #expect(history.correctCount == 2, "\(name)")
            #expect(abs(history.averageMillis - 2000) < 0.0001, "\(name)")
        }
    }

    @Test("recording a wrong answer counts the attempt without a timing")
    func recordsIncorrect() throws {
        for (name, store) in try stores() {
            let fact = Fact(a: 6, b: 9)
            store.recordIncorrect(fact, at: start)

            let history = try #require(store.history()["6x9"], "\(name)")
            #expect(history.attempts == 1, "\(name)")
            #expect(history.correctCount == 0, "\(name)")
        }
    }

    @Test("runs are returned only for their own configuration, newest data intact")
    func runsAreScopedByConfig() throws {
        for (name, store) in try stores() {
            store.recordRun(configKey: "a", score: 10, answered: 12, at: start)
            store.recordRun(configKey: "a", score: 4, answered: 5, at: start.addingTimeInterval(60))
            store.recordRun(configKey: "b", score: 99, answered: 99, at: start)

            let runsForA = store.runs(forConfigKey: "a")
            #expect(runsForA.count == 2, "\(name)")
            #expect(Set(runsForA.map(\.score)) == [10, 4], "\(name)")
            #expect(store.runs(forConfigKey: "b").map(\.score) == [99], "\(name)")
            #expect(store.runs(forConfigKey: "c").isEmpty, "\(name)")
        }
    }

    @Test("mastery levels reflect recorded history and default to Not yet")
    func masteryLevels() throws {
        for (name, store) in try stores() {
            let mastered = Fact(a: 2, b: 3)
            for _ in 0..<3 { store.recordCorrect(mastered, millis: 1200, at: start) }
            store.recordIncorrect(Fact(a: 11, b: 12), at: start)

            let levels = store.masteryLevels()
            #expect(levels["2x3"] == .mastered, "\(name)")
            #expect(levels["11x12"] == .gettingThere, "\(name)")
            #expect(levels["9x9"] == nil, "\(name) invented history")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'InMemoryProgressStore' in scope`.

- [ ] **Step 3: Create `Tables/Model/ProgressRecording.swift`**

```swift
import Foundation

/// The only surface `GameSession` needs from persistence. Keeping it this
/// narrow is what lets a whole game be played out in a unit test.
@MainActor
protocol ProgressRecording: AnyObject {
    func history() -> [String: FactHistory]
    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date)
    func recordIncorrect(_ fact: Fact, at date: Date)
    func recordRun(configKey: String, score: Int, answered: Int, at date: Date)
    func runs(forConfigKey key: String) -> [RunRecord]
}

extension ProgressRecording {
    func masteryLevels() -> [String: MasteryLevel] {
        history().mapValues(Mastery.level(for:))
    }
}
```

- [ ] **Step 4: Create `Tables/Model/InMemoryProgressStore.swift`**

```swift
import Foundation

/// Used by tests and SwiftUI previews. Behaviour must match
/// `SwiftDataProgressStore` exactly — `ProgressStoreTests` runs the same suite
/// against both.
@MainActor
final class InMemoryProgressStore: ProgressRecording {
    private var stats: [String: FactStat] = [:]
    private var runs: [RunRecord] = []
    private var runKeys: [Date: String] = [:]

    init() {}

    private func stat(for fact: Fact) -> FactStat {
        if let existing = stats[fact.key] { return existing }
        let created = FactStat(fact: fact)
        stats[fact.key] = created
        return created
    }

    func history() -> [String: FactHistory] {
        stats.mapValues(\.history)
    }

    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date) {
        stat(for: fact).recordCorrect(millis: millis, at: date)
    }

    func recordIncorrect(_ fact: Fact, at date: Date) {
        stat(for: fact).recordIncorrect(at: date)
    }

    func recordRun(configKey: String, score: Int, answered: Int, at date: Date) {
        let record = RunRecord(score: score, answered: answered, date: date)
        runs.append(record)
        runKeys[date] = configKey
    }

    func runs(forConfigKey key: String) -> [RunRecord] {
        runs.filter { runKeys[$0.date] == key }
    }
}
```

- [ ] **Step 5: Create `Tables/Model/SwiftDataProgressStore.swift`**

```swift
import Foundation
import SwiftData

@MainActor
final class SwiftDataProgressStore: ProgressRecording {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func history() -> [String: FactHistory] {
        let stats = (try? context.fetch(FetchDescriptor<FactStat>())) ?? []
        return Dictionary(uniqueKeysWithValues: stats.map { ($0.key, $0.history) })
    }

    func recordCorrect(_ fact: Fact, millis: Double?, at date: Date) {
        stat(for: fact).recordCorrect(millis: millis, at: date)
        save()
    }

    func recordIncorrect(_ fact: Fact, at date: Date) {
        stat(for: fact).recordIncorrect(at: date)
        save()
    }

    func recordRun(configKey: String, score: Int, answered: Int, at date: Date) {
        context.insert(GameRun(configKey: configKey, score: score, answered: answered, date: date))
        save()
    }

    func runs(forConfigKey key: String) -> [RunRecord] {
        let descriptor = FetchDescriptor<GameRun>(
            predicate: #Predicate { $0.configKey == key },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.record)
    }

    private func stat(for fact: Fact) -> FactStat {
        let key = fact.key
        var descriptor = FetchDescriptor<FactStat>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { return existing }
        let created = FactStat(fact: fact)
        context.insert(created)
        return created
    }

    /// Progress data is worth nothing if losing a single write crashes a
    /// child's game, so a failed save is swallowed rather than thrown.
    private func save() {
        try? context.save()
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS. Both stores run the same suite, so any divergence between them fails here.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add progress store behind a narrow protocol

One suite runs against both the SwiftData store and the in-memory one,
so the test double cannot drift from real behaviour."
```

---

### Task 10: Settings and feedback services

**Files:**
- Create: `Tables/Services/AppSettings.swift`, `Tables/Services/FeedbackPlayer.swift`
- Test: `TablesTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@MainActor @Observable final class AppSettings` with `var soundEnabled: Bool`, `var hapticsEnabled: Bool`, `var multipleChoiceOptionCount: Int`, `init(defaults: UserDefaults = .standard)`, `static let optionCountChoices = [4, 6]`
  - `@MainActor protocol FeedbackPlaying: AnyObject { func correct(); func incorrect() }`
  - `@MainActor final class FeedbackPlayer: FeedbackPlaying` with `init(settings: AppSettings)`
  - `@MainActor final class SilentFeedbackPlayer: FeedbackPlaying`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/AppSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct AppSettingsTests {

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("a fresh install has sound and haptics on and six options")
    func defaults() {
        let settings = AppSettings(defaults: freshDefaults("test.defaults"))
        #expect(settings.soundEnabled)
        #expect(settings.hapticsEnabled)
        #expect(settings.multipleChoiceOptionCount == 6)
    }

    @Test("changes survive a relaunch")
    func changesPersist() {
        let defaults = freshDefaults("test.persist")
        let first = AppSettings(defaults: defaults)
        first.soundEnabled = false
        first.hapticsEnabled = false
        first.multipleChoiceOptionCount = 4

        let second = AppSettings(defaults: defaults)
        #expect(!second.soundEnabled)
        #expect(!second.hapticsEnabled)
        #expect(second.multipleChoiceOptionCount == 4)
    }

    @Test("an out-of-range option count falls back to six")
    func optionCountIsClamped() {
        let defaults = freshDefaults("test.clamp")
        defaults.set(9, forKey: "settings.multipleChoiceOptionCount")
        #expect(AppSettings(defaults: defaults).multipleChoiceOptionCount == 6)
    }

    @Test("only four and six are offered")
    func choices() {
        #expect(AppSettings.optionCountChoices == [4, 6])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'AppSettings' in scope`.

- [ ] **Step 3: Create `Tables/Services/AppSettings.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let optionCountChoices = [4, 6]

    private static let soundKey = "settings.soundEnabled"
    private static let hapticsKey = "settings.hapticsEnabled"
    private static let optionCountKey = "settings.multipleChoiceOptionCount"

    @ObservationIgnored private let defaults: UserDefaults

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundKey) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }

    var multipleChoiceOptionCount: Int {
        didSet { defaults.set(multipleChoiceOptionCount, forKey: Self.optionCountKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` distinguishes "off" from "never set".
        self.soundEnabled = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        let stored = defaults.object(forKey: Self.optionCountKey) as? Int ?? 6
        self.multipleChoiceOptionCount = Self.optionCountChoices.contains(stored) ? stored : 6
    }
}
```

- [ ] **Step 4: Create `Tables/Services/FeedbackPlayer.swift`**

```swift
import AVFoundation
import UIKit

@MainActor
protocol FeedbackPlaying: AnyObject {
    func correct()
    func incorrect()
}

/// Used in tests and previews, where audio and haptics are noise.
@MainActor
final class SilentFeedbackPlayer: FeedbackPlaying {
    init() {}
    func correct() {}
    func incorrect() {}
}

/// Haptics plus two synthesised tones.
///
/// The tones are generated rather than shipped as assets: there is nothing to
/// licence, nothing to bundle, and the result is a soft sine rather than a
/// game-show sting.
@MainActor
final class FeedbackPlayer: FeedbackPlaying {
    private let settings: AppSettings
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var correctBuffer: AVAudioPCMBuffer?
    private var incorrectBuffer: AVAudioPCMBuffer?
    private var isEngineReady = false

    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func correct() {
        if settings.hapticsEnabled {
            impact.impactOccurred()
        }
        play(\.correctBuffer)
    }

    func incorrect() {
        if settings.hapticsEnabled {
            notification.notificationOccurred(.warning)
        }
        play(\.incorrectBuffer)
    }

    func prepare() {
        impact.prepare()
        notification.prepare()
    }

    private func play(_ keyPath: KeyPath<FeedbackPlayer, AVAudioPCMBuffer?>) {
        guard settings.soundEnabled else { return }
        startEngineIfNeeded()
        guard let buffer = self[keyPath: keyPath] else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    private func startEngineIfNeeded() {
        guard !isEngineReady else { return }
        isEngineReady = true

        // .ambient means the hardware silent switch and any music already
        // playing both win. A practice app should never take over the device.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        correctBuffer = Self.tone(frequency: 880, duration: 0.16, format: format)
        incorrectBuffer = Self.tone(frequency: 320, duration: 0.18, format: format)
        try? engine.start()
    }

    /// Fast attack, gentle exponential decay — a soft knock rather than a beep.
    private static func tone(
        frequency: Double,
        duration: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let attackFrames = sampleRate * 0.005
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let attack = min(1, Double(frame) / attackFrames)
            let decay = exp(-6 * time / duration)
            channel[frame] = Float(sin(2 * .pi * frequency * time) * attack * decay * 0.22)
        }
        return buffer
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add settings and feedback services

Sound, haptics and multiple-choice option count persist across launches.
Tones are synthesised, so there are no audio assets to licence."
```

---

### Task 11: Game session

**Files:**
- Create: `Tables/Game/GameSession.swift`
- Test: `TablesTests/GameSessionTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 3–10.
- Produces: `@MainActor @Observable final class GameSession` with
  - `enum Phase: Equatable { case asking; case feedback(isCorrect: Bool, text: String); case finished }`
  - `enum EndOutcome { case abandoned, finished }`
  - `struct Summary { let config: GameConfig; let score: Int; let answered: Int; let board: ScoreBoardResult }`
  - `init(config: GameConfig, store: any ProgressRecording, optionCount: Int, feedback: any FeedbackPlaying, rng: any RandomNumberGenerator)`
  - state: `fact`, `options`, `padValue`, `phase`, `score`, `answered`, `secondsRemaining`, `pickedValue`, `revealAnswer`, `isFadingOut`, `summary`
  - derived: `isLowTime`, `timeText`, `revisionProgressText`, `endLabel`, `canSubmitPad`
  - commands: `start(now:)`, `submit(_:now:)`, `padAppend(_:)`, `padDelete()`, `padSubmit(now:)`, `tick(now:)`, `endEarly(now:) -> EndOutcome`, `pause(now:)`, `resume(now:)`

Time is never read from the system inside this class. Every entry point takes `now`, and a single `tick(now:)` advances feedback holds, cross-fades and the countdown. That is what makes a full 60-second game testable in microseconds.

- [ ] **Step 1: Write the failing test**

Create `TablesTests/GameSessionTests.swift`:

```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct GameSessionTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSession(
        mode: GameMode = .countdown,
        length: GameLength = .seconds(60),
        answerMode: AnswerMode = .multipleChoice,
        tables: Set<Int> = [3, 7],
        store: (any ProgressRecording)? = nil
    ) -> (GameSession, any ProgressRecording) {
        let backing = store ?? InMemoryProgressStore()
        let config = GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
        let session = GameSession(
            config: config,
            store: backing,
            optionCount: 6,
            feedback: SilentFeedbackPlayer(),
            rng: SeededRandom(seed: 17)
        )
        return (session, backing)
    }

    /// Advances the session to `date` in small steps, as the real timer does.
    private func run(_ session: GameSession, from: Date, to: Date) {
        var now = from
        while now < to {
            now = min(to, now.addingTimeInterval(0.05))
            session.tick(now: now)
        }
    }

    // MARK: Countdown

    @Test("a correct answer scores and moves on")
    func countdownCorrectScores() {
        let (session, _) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer, now: start.addingTimeInterval(1))
        #expect(session.score == 1)
        #expect(session.answered == 1)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(isCorrect)
            #expect(!text.isEmpty)
        } else {
            Issue.record("expected feedback phase, got \(session.phase)")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(3))
        #expect(session.phase == .asking)
        #expect(session.fact != first)
    }

    @Test("a wrong answer keeps the same question and costs no point")
    func countdownWrongRetries() {
        let (session, _) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 1, now: start.addingTimeInterval(1))
        #expect(session.score == 0)
        #expect(session.answered == 0)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(!isCorrect)
            #expect(text == "Not quite \u{2014} try again")
        } else {
            Issue.record("expected feedback phase, got \(session.phase)")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(3))
        #expect(session.phase == .asking)
        #expect(session.fact == first, "the question changed after a wrong answer")
        #expect(session.pickedValue == nil)
        #expect(session.padValue.isEmpty)
    }

    @Test("a retry after a wrong answer scores but records no timing")
    func countdownRetryRecordsNoTiming() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 1, now: start.addingTimeInterval(1))
        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(2))
        session.submit(first.answer, now: start.addingTimeInterval(3))

        #expect(session.score == 1)
        let history = store.history()[first.key]!
        #expect(history.attempts == 2)
        // correctCount in FactHistory counts *timed* correct answers only.
        #expect(history.correctCount == 0, "an untrustworthy retry was timed")
        #expect(history.averageMillis == 0)
    }

    @Test("a first-attempt correct answer is timed")
    func countdownFirstAttemptIsTimed() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer, now: start.addingTimeInterval(1.5))
        let history = store.history()[first.key]!
        #expect(history.correctCount == 1)
        #expect(abs(history.averageMillis - 1500) < 50)
    }

    @Test("the clock runs down and ends the game at zero")
    func countdownExpires() {
        let (session, store) = makeSession(length: .seconds(30))
        session.start(now: start)
        #expect(session.secondsRemaining == 30)

        run(session, from: start, to: start.addingTimeInterval(10))
        #expect(session.secondsRemaining == 20)
        #expect(session.phase != .finished)

        run(session, from: start.addingTimeInterval(10), to: start.addingTimeInterval(31))
        #expect(session.phase == .finished)
        #expect(session.secondsRemaining == 0)
        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("the clock reads as low in the final ten seconds")
    func lowTimeThreshold() {
        let (session, _) = makeSession(length: .seconds(30))
        session.start(now: start)
        #expect(!session.isLowTime)
        run(session, from: start, to: start.addingTimeInterval(20.5))
        #expect(session.isLowTime)
    }

    @Test("the timer text is minutes and seconds")
    func timerText() {
        let (session, _) = makeSession(length: .seconds(120))
        session.start(now: start)
        #expect(session.timeText == "2:00")
        run(session, from: start, to: start.addingTimeInterval(61))
        #expect(session.timeText == "0:59")
    }

    @Test("backgrounding pauses the clock rather than punishing an interruption")
    func pauseAndResume() {
        let (session, _) = makeSession(length: .seconds(60))
        session.start(now: start)
        run(session, from: start, to: start.addingTimeInterval(10))
        #expect(session.secondsRemaining == 50)

        session.pause(now: start.addingTimeInterval(10))
        // Thirty seconds elapse in the background.
        session.tick(now: start.addingTimeInterval(40))
        #expect(session.secondsRemaining == 50, "the clock ran while backgrounded")

        session.resume(now: start.addingTimeInterval(40))
        session.tick(now: start.addingTimeInterval(40))
        #expect(session.secondsRemaining == 50)
        run(session, from: start.addingTimeInterval(40), to: start.addingTimeInterval(45))
        #expect(session.secondsRemaining == 45)
    }

    @Test("a question interrupted by backgrounding is not timed as slow")
    func pauseDoesNotSkewFactTiming() {
        let (session, store) = makeSession()
        session.start(now: start)
        let first = session.fact

        session.pause(now: start.addingTimeInterval(1))
        session.resume(now: start.addingTimeInterval(300))
        session.submit(first.answer, now: start.addingTimeInterval(301))

        let history = store.history()[first.key]!
        #expect(history.averageMillis < 3000, "a background pause was counted as thinking time")
    }

    // MARK: Revision

    @Test("a wrong answer reveals the fact and moves on")
    func revisionRevealsAndAdvances() {
        let (session, _) = makeSession(mode: .revision, length: .questions(10))
        session.start(now: start)
        let first = session.fact

        session.submit(first.answer + 3, now: start.addingTimeInterval(1))
        #expect(session.answered == 1)
        #expect(session.score == 0)
        #expect(session.revealAnswer)
        if case .feedback(let isCorrect, let text) = session.phase {
            #expect(!isCorrect)
            #expect(text == first.revealed)
        } else {
            Issue.record("expected feedback phase")
        }

        run(session, from: start.addingTimeInterval(1), to: start.addingTimeInterval(4))
        #expect(session.fact != first)
        #expect(session.phase == .asking)
    }

    @Test("a fixed-length session ends after exactly the chosen number of questions")
    func revisionFixedLengthTerminates() {
        let (session, store) = makeSession(mode: .revision, length: .questions(10))
        session.start(now: start)

        var now = start
        for index in 1...10 {
            now = now.addingTimeInterval(1)
            session.submit(session.fact.answer, now: now)
            #expect(session.answered == index)
            let next = now.addingTimeInterval(3)
            run(session, from: now, to: next)
            now = next
        }

        #expect(session.phase == .finished)
        #expect(session.answered == 10)
        #expect(session.score == 10)
        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("an endless session keeps going until the child finishes it")
    func endlessRunsOn() {
        let (session, _) = makeSession(mode: .revision, length: .endless)
        session.start(now: start)
        #expect(session.endLabel == "Finish")

        var now = start
        for _ in 1...25 {
            now = now.addingTimeInterval(1)
            session.submit(session.fact.answer, now: now)
            let next = now.addingTimeInterval(3)
            run(session, from: now, to: next)
            now = next
        }
        #expect(session.phase != .finished)
        #expect(session.answered == 25)

        #expect(session.endEarly(now: now) == .finished)
        #expect(session.phase == .finished)
    }

    @Test("the progress pill counts up, and shows a target when there is one")
    func revisionProgressText() {
        let (fixed, _) = makeSession(mode: .revision, length: .questions(20))
        fixed.start(now: start)
        #expect(fixed.revisionProgressText == "0/20")

        let (endless, _) = makeSession(mode: .revision, length: .endless)
        endless.start(now: start)
        #expect(endless.revisionProgressText == "0")
    }

    // MARK: Ending early

    @Test("quitting before answering anything records nothing")
    func abandoningRecordsNothing() {
        let (session, store) = makeSession()
        session.start(now: start)
        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .abandoned)
        #expect(store.runs(forConfigKey: session.config.configKey).isEmpty)
        #expect(session.phase != .finished)
    }

    @Test("quitting after answering records the run")
    func endingEarlyRecordsTheRun() {
        let (session, store) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))

        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)
        #expect(session.phase == .finished)
        let runs = store.runs(forConfigKey: session.config.configKey)
        #expect(runs.count == 1)
        #expect(runs[0].score == 1)
    }

    @Test("a second end tap does not record the run twice")
    func endingTwiceRecordsOneRun() {
        let (session, store) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))

        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)
        // A double-tap, or a race with the clock finishing on its own.
        #expect(session.endEarly(now: start.addingTimeInterval(2)) == .finished)

        #expect(store.runs(forConfigKey: session.config.configKey).count == 1)
    }

    @Test("the summary carries the score board")
    func summaryCarriesTheBoard() {
        let store = InMemoryProgressStore()
        let (first, _) = makeSession(store: store)
        first.start(now: start)
        first.submit(first.fact.answer, now: start.addingTimeInterval(1))
        _ = first.endEarly(now: start.addingTimeInterval(2))

        let (second, _) = makeSession(store: store)
        second.start(now: start.addingTimeInterval(100))
        second.submit(second.fact.answer, now: start.addingTimeInterval(101))
        // Advance past the feedback hold to the next question before answering
        // again — two submits at the same instant would be one scoring answer
        // plus one swallowed double-tap, leaving the second run tied with the
        // first rather than beating it.
        run(second, from: start.addingTimeInterval(101), to: start.addingTimeInterval(103))
        second.submit(second.fact.answer, now: start.addingTimeInterval(104))
        _ = second.endEarly(now: start.addingTimeInterval(120))

        let summary = try! #require(second.summary)
        #expect(second.score == 2)
        #expect(summary.board.previousBest == 1)
        #expect(summary.board.isNewBest)
    }

    // MARK: Number pad

    @Test("the pad builds a value, deletes, and caps at three digits")
    func padEditing() {
        let (session, _) = makeSession(answerMode: .numberPad)
        session.start(now: start)

        session.padAppend(4)
        session.padAppend(2)
        #expect(session.padValue == "42")
        #expect(session.canSubmitPad)

        session.padDelete()
        #expect(session.padValue == "4")

        session.padAppend(1)
        session.padAppend(2)
        session.padAppend(3)
        #expect(session.padValue == "412", "the pad should stop at three digits")
    }

    @Test("submitting an empty pad does nothing")
    func padWillNotSubmitEmpty() {
        let (session, _) = makeSession(answerMode: .numberPad)
        session.start(now: start)
        #expect(!session.canSubmitPad)
        session.padSubmit(now: start.addingTimeInterval(1))
        #expect(session.phase == .asking)
        #expect(session.answered == 0)
    }

    @Test("multiple choice offers the configured number of options, including the answer")
    func optionsMatchSettings() {
        let (session, _) = makeSession()
        session.start(now: start)
        #expect(session.options.count == 6)
        #expect(session.options.contains(session.fact.answer))
    }

    @Test("answers are ignored while feedback is showing")
    func inputIsIgnoredDuringFeedback() {
        let (session, _) = makeSession()
        session.start(now: start)
        session.submit(session.fact.answer, now: start.addingTimeInterval(1))
        session.submit(session.fact.answer, now: start.addingTimeInterval(1.1))
        #expect(session.score == 1, "a double tap scored twice")
    }
}
```

`Issue.record` is Swift Testing's way of failing from inside a control-flow branch — use it, not `#expect(false)`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'GameSession' in scope`.

- [ ] **Step 3: Create `Tables/Game/GameSession.swift`**

```swift
import Foundation
import Observation

/// Drives one game from first question to final score.
///
/// Nothing here reads the system clock. Every command takes `now`, and
/// `tick(now:)` advances holds, cross-fades and the countdown — so a full
/// two-minute game plays out in a unit test in microseconds, and pausing for a
/// backgrounded app is a matter of shifting deadlines rather than special
/// cases.
@MainActor
@Observable
final class GameSession {

    enum Phase: Equatable {
        case asking
        case feedback(isCorrect: Bool, text: String)
        case finished
    }

    enum EndOutcome: Equatable {
        case abandoned
        case finished
    }

    struct Summary {
        let config: GameConfig
        let score: Int
        let answered: Int
        let board: ScoreBoardResult
    }

    // Hold durations, carried over from the design prototype.
    private static let countdownCorrectHold: TimeInterval = 0.75
    private static let countdownWrongHold: TimeInterval = 0.85
    private static let revisionHold: TimeInterval = 1.30
    private static let fadeDuration: TimeInterval = 0.24
    static let lowTimeThreshold = 10

    private static let praise = [
        "Nice!", "Correct!", "Well done!", "Great!", "Yes!",
        "Spot on!", "Brilliant!", "Perfect!", "That's it!", "Lovely!"
    ]

    let config: GameConfig

    private(set) var fact: Fact
    private(set) var options: [Int] = []
    private(set) var padValue: String = ""
    private(set) var phase: Phase = .asking
    private(set) var score = 0
    private(set) var answered = 0
    private(set) var secondsRemaining = 0
    private(set) var pickedValue: Int?
    private(set) var revealAnswer = false
    private(set) var isFadingOut = false
    private(set) var summary: Summary?

    @ObservationIgnored private let store: any ProgressRecording
    @ObservationIgnored private let feedback: any FeedbackPlaying
    @ObservationIgnored private let picker: QuestionPicker
    @ObservationIgnored private let optionCount: Int
    @ObservationIgnored private var rng: AnyRandomGenerator

    @ObservationIgnored private var questionStartedAt: Date
    @ObservationIgnored private var firstAttemptWasWrong = false
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var holdUntil: Date?
    @ObservationIgnored private var fadeUntil: Date?
    @ObservationIgnored private var pausedAt: Date?

    init(
        config: GameConfig,
        store: any ProgressRecording,
        optionCount: Int,
        feedback: any FeedbackPlaying,
        rng: any RandomNumberGenerator
    ) {
        self.config = config
        self.store = store
        self.optionCount = optionCount
        self.feedback = feedback
        self.rng = AnyRandomGenerator(rng)
        self.picker = QuestionPicker(facts: config.facts, mode: config.mode)
        self.fact = config.facts.first ?? Fact(a: 1, b: 1)
        self.questionStartedAt = Date(timeIntervalSince1970: 0)
    }

    // MARK: Derived state

    var isLowTime: Bool {
        config.mode == .countdown && secondsRemaining <= Self.lowTimeThreshold
    }

    var timeText: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var revisionProgressText: String {
        if case .questions(let target) = config.length { return "\(answered)/\(target)" }
        return "\(answered)"
    }

    var endLabel: String {
        config.mode == .revision && config.length == .endless ? "Finish" : "End session"
    }

    var canSubmitPad: Bool { !padValue.isEmpty }

    var feedbackText: String {
        if case .feedback(_, let text) = phase { return text }
        return ""
    }

    // MARK: Commands

    func start(now: Date) {
        score = 0
        answered = 0
        summary = nil
        pausedAt = nil
        if case .seconds(let total) = config.length {
            deadline = now.addingTimeInterval(TimeInterval(total))
            secondsRemaining = total
        }
        nextQuestion(now: now)
    }

    func submit(_ value: Int, now: Date) {
        guard phase == .asking else { return }
        let isCorrect = value == fact.answer
        let millis = now.timeIntervalSince(questionStartedAt) * 1000
        pickedValue = value

        switch config.mode {
        case .countdown:
            if isCorrect {
                // A retry proves knowledge but not speed, so it goes untimed.
                store.recordCorrect(fact, millis: firstAttemptWasWrong ? nil : millis, at: now)
                score += 1
                answered += 1
                feedback.correct()
                phase = .feedback(isCorrect: true, text: Self.praise.randomElement(using: &rng)!)
                holdUntil = now.addingTimeInterval(Self.countdownCorrectHold)
            } else {
                store.recordIncorrect(fact, at: now)
                firstAttemptWasWrong = true
                feedback.incorrect()
                phase = .feedback(isCorrect: false, text: "Not quite \u{2014} try again")
                holdUntil = now.addingTimeInterval(Self.countdownWrongHold)
            }

        case .revision:
            answered += 1
            if isCorrect {
                store.recordCorrect(fact, millis: millis, at: now)
                score += 1
                feedback.correct()
                phase = .feedback(isCorrect: true, text: Self.praise.randomElement(using: &rng)!)
            } else {
                store.recordIncorrect(fact, at: now)
                revealAnswer = true
                feedback.incorrect()
                phase = .feedback(isCorrect: false, text: fact.revealed)
            }
            holdUntil = now.addingTimeInterval(Self.revisionHold)
        }
    }

    func padAppend(_ digit: Int) {
        guard phase == .asking, padValue.count < 3 else { return }
        padValue.append(String(digit))
    }

    func padDelete() {
        guard phase == .asking else { return }
        padValue = String(padValue.dropLast())
    }

    func padSubmit(now: Date) {
        guard let value = Int(padValue) else { return }
        submit(value, now: now)
    }

    func tick(now: Date) {
        guard phase != .finished, pausedAt == nil else { return }

        if let deadline {
            secondsRemaining = max(0, Int(ceil(deadline.timeIntervalSince(now))))
            if now >= deadline {
                finish(now: now)
                return
            }
        }

        if let fadeUntil, now >= fadeUntil {
            nextQuestion(now: now)
            return
        }

        if let hold = holdUntil, now >= hold {
            holdUntil = nil
            if config.mode == .countdown, case .feedback(false, _) = phase {
                // Retry the same question rather than moving on.
                phase = .asking
                pickedValue = nil
                padValue = ""
                return
            }
            if case .questions(let target) = config.length, answered >= target {
                finish(now: now)
                return
            }
            isFadingOut = true
            fadeUntil = now.addingTimeInterval(Self.fadeDuration)
        }
    }

    func endEarly(now: Date) -> EndOutcome {
        // A second tap on End/Finish, or a race with the clock finishing on
        // its own, must not record the run twice or recompute the board.
        guard phase != .finished else { return .finished }
        guard answered > 0 else { return .abandoned }
        finish(now: now)
        return .finished
    }

    /// The app went to the background. Deadlines resume where they left off.
    func pause(now: Date) {
        guard pausedAt == nil, phase != .finished else { return }
        pausedAt = now
    }

    func resume(now: Date) {
        guard phase != .finished else { pausedAt = nil; return }
        guard let pausedAt else { return }
        let elapsed = now.timeIntervalSince(pausedAt)
        deadline = deadline?.addingTimeInterval(elapsed)
        holdUntil = holdUntil?.addingTimeInterval(elapsed)
        fadeUntil = fadeUntil?.addingTimeInterval(elapsed)
        questionStartedAt = questionStartedAt.addingTimeInterval(elapsed)
        self.pausedAt = nil
    }

    // MARK: Internals

    private func nextQuestion(now: Date) {
        // nil only on the very first question, when there is nothing to avoid.
        let previous = (answered > 0 || firstAttemptWasWrong) ? fact : nil
        fact = picker.next(history: store.history(), previous: previous, using: &rng)
        options = config.answerMode == .multipleChoice
            ? DistractorGenerator.options(for: fact, count: optionCount, using: &rng)
            : []
        padValue = ""
        pickedValue = nil
        revealAnswer = false
        isFadingOut = false
        firstAttemptWasWrong = false
        holdUntil = nil
        fadeUntil = nil
        questionStartedAt = now
        phase = .asking
    }

    private func finish(now: Date) {
        deadline = nil
        holdUntil = nil
        fadeUntil = nil
        isFadingOut = false
        secondsRemaining = 0

        let previousRuns = store.runs(forConfigKey: config.configKey)
        let current = RunRecord(score: score, answered: answered, date: now)
        store.recordRun(configKey: config.configKey, score: score, answered: answered, at: now)

        summary = Summary(
            config: config,
            score: score,
            answered: answered,
            board: ScoreBoard.evaluate(previousRuns: previousRuns, current: current)
        )
        phase = .finished
    }
}
```

- [ ] **Step 3b: Add the RNG box**

`picker.next` and `randomElement(using:)` take `inout some RandomNumberGenerator`. Swift does **not** implicitly open an existential for an `inout` parameter, so storing `any RandomNumberGenerator` and writing `&rng` will not compile. Box it in a concrete conforming type instead.

Add to the top of `Tables/Game/GameSession.swift`, above the class:

```swift
/// A concrete `RandomNumberGenerator` wrapping any other one.
///
/// Needed because Swift will not implicitly open an existential passed as
/// `inout`, and every random API in the standard library takes its generator
/// that way. Tests inject a seeded generator through this; the app injects
/// `SystemRandomNumberGenerator`.
struct AnyRandomGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}
```

With `rng` typed as `AnyRandomGenerator`, `&rng` works directly at every call site — `picker.next(..., using: &rng)`, `DistractorGenerator.options(..., using: &rng)` and `Self.praise.randomElement(using: &rng)!` all compile as written above, with no wrapping.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -30`

Expected: PASS — all `GameSessionTests` cases. If `pauseDoesNotSkewFactTiming` fails, `questionStartedAt` is not being shifted in `resume`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add game session state machine

Drives both modes through an injected clock and RNG, so a full game runs
in a test without timers. Backgrounding shifts deadlines rather than
punishing an interruption."
```

---

## A note on the view tasks (12–19)

SwiftUI views are not usefully unit-tested in isolation, and every behavioural
rule in this app already lives in a tested type. So the view tasks verify
differently, and each one states how:

1. `xcodebuild build` must succeed with no warnings introduced.
2. Any *logic* the view introduces is extracted into a testable type and tested.
3. The task lists what to confirm on screen, and Task 20 adds the UI smoke test.

Do not skip step 3. Building is not the same as looking.

---

### Task 12: Design system components

**Files:**
- Create: `Tables/DesignSystem/Components/Eyebrow.swift`, `Card.swift`, `PillButton.swift`, `TileButton.swift`, `Chip.swift`, `BackButton.swift`, `BrandMark.swift`
- Test: none (pure presentation; verified by build and by the screens that use them)

**Interfaces:**
- Consumes: `Palette`, `Metrics`, `Motion`, `Typography` (Task 2).
- Produces:
  - `struct Eyebrow: View { init(_ text: String, color: Color = .inkMuted) }`
  - `struct Card<Content: View>: View { init(@ViewBuilder content: () -> Content) }`
  - `struct PillButton: View { init(_ title: String, style: Style = .primary, isEnabled: Bool = true, action: @escaping () -> Void) }` with `enum Style { case primary, ghost }`
  - `struct TileButton: View { init(label: String, state: TileState, font: Font, action: @escaping () -> Void) }` and
    `enum TileState { case neutral, selected, correct, incorrect }`
  - `struct Chip: View { init(_ title: String, isSelected: Bool, action: @escaping () -> Void) }`
  - `struct StatusChip: View { init(_ title: String) }` — the static lilac "Soon" pill
  - `struct BackButton: View { init(action: @escaping () -> Void) }`
  - `struct BrandMark: View`

- [ ] **Step 1: Create `Tables/DesignSystem/Components/Eyebrow.swift`**

```swift
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
```

- [ ] **Step 2: Create `Tables/DesignSystem/Components/Card.swift`**

```swift
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
```

- [ ] **Step 3: Create `Tables/DesignSystem/Components/PillButton.swift`**

```swift
import SwiftUI

struct PillButton: View {
    enum Style {
        case primary
        case ghost
    }

    private let title: String
    private let style: Style
    private let isEnabled: Bool
    private let action: () -> Void

    init(
        _ title: String,
        style: Style = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.isEnabled = isEnabled
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
    }
}
```

- [ ] **Step 4: Create `Tables/DesignSystem/Components/TileButton.swift`**

```swift
import SwiftUI

enum TileState {
    case neutral
    case selected
    case correct
    case incorrect

    var fill: Color {
        switch self {
        case .neutral: .paper
        case .selected: .skyTint
        case .correct: .sage
        case .incorrect: .blush
        }
    }

    var stroke: Color {
        switch self {
        case .neutral: .line
        case .selected: .sky
        case .correct: .sage
        case .incorrect: .blush
        }
    }

    var text: Color {
        switch self {
        case .neutral: .ink
        case .selected: .skyText
        case .correct: .sageText
        case .incorrect: .blushText
        }
    }

    /// Only a tile the child just touched pops.
    var shouldPop: Bool {
        self == .correct || self == .incorrect
    }
}

/// A gently rounded square with a visible 2pt stroke. State is communicated by
/// fill colour above all else.
struct TileButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let label: String
    private let state: TileState
    private let font: Font
    private let verticalPadding: CGFloat
    private let action: () -> Void

    @State private var scale: CGFloat = 1

    init(
        label: String,
        state: TileState,
        font: Font,
        verticalPadding: CGFloat = 18,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.state = state
        self.font = font
        self.verticalPadding = verticalPadding
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(font)
                .foregroundStyle(state.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(state.fill)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                        .strokeBorder(state.stroke, lineWidth: Metrics.strokeTile)
                }
                .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: state)
        .onChange(of: state) { _, newState in
            guard newState.shouldPop, !reduceMotion else { return }
            withAnimation(.easeOut(duration: Motion.pop / 2)) { scale = 1.12 }
            withAnimation(.easeIn(duration: Motion.pop / 2).delay(Motion.pop / 2)) { scale = 1 }
        }
    }
}
```

- [ ] **Step 5: Create `Tables/DesignSystem/Components/Chip.swift`**

```swift
import SwiftUI

/// Full pill, used for the length options on the setup screen.
struct Chip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Color.paper : Color.ink)
                .padding(.vertical, 11)
                .padding(.horizontal, Metrics.space4)
                .background(isSelected ? Color.ink : Color.paper)
                .clipShape(Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.ink : Color.line, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: isSelected)
    }
}

/// A non-interactive status pill, e.g. "Soon" against the Voice answer mode.
struct StatusChip: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(Typography.ui(11, weight: .semibold, relativeTo: .caption))
            .foregroundStyle(Color.lilacText)
            .padding(.vertical, 3)
            .padding(.horizontal, Metrics.space3)
            .background(Color.lilacTint)
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 6: Create `Tables/DesignSystem/Components/BackButton.swift`**

```swift
import SwiftUI

struct BackButton: View {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: Metrics.hitMin, height: Metrics.hitMin)
                .background(Color.paper)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(Color.border, lineWidth: Metrics.strokeCard) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
```

- [ ] **Step 7: Create `Tables/DesignSystem/Components/BrandMark.swift`**

```swift
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
```

- [ ] **Step 8: Verify the build**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -20`

Expected: no output on success. Any warning about an unused variable or an ambiguous type is a defect — fix it now rather than leaving it for a later task.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "Add shared design system components

Eyebrow, Card, PillButton, TileButton, Chip, BackButton and BrandMark,
with the tile pop gated on Reduce Motion."
```

---

### Task 13: App shell, navigation and home screen

**Files:**
- Modify: `Tables/TablesApp.swift`
- Create: `Tables/Features/AppRouter.swift`, `Tables/Features/Home/HomeView.swift`
- Test: `TablesTests/AppRouterTests.swift`

**Interfaces:**
- Consumes: components (Task 12), `GameConfig` (Task 3), `AppSettings` (Task 10), `GameSession.Summary` (Task 11).
- Produces:
  - `enum Route: Hashable { case setup(GameMode); case game(GameConfig); case results; case progress }`
  - `@MainActor @Observable final class AppRouter` with `var path: [Route]`, `var isShowingSettings: Bool`, `private(set) var summary: GameSession.Summary?`, and `func openSetup(_:)`, `func startGame(_:)`, `func showResults(_:)`, `func playAgain()`, `func goHome()`, `func openProgress()`
  - `struct HomeView: View`
  - `struct PhoneColumn<Content: View>: View` — caps content at `Metrics.contentMaxWidth` and centres it, so iPad reads as designed

- [ ] **Step 1: Write the failing test**

Create `TablesTests/AppRouterTests.swift`:

```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct AppRouterTests {

    private func summary(score: Int) -> GameSession.Summary {
        GameSession.Summary(
            config: .default,
            score: score,
            answered: score,
            board: ScoreBoard.evaluate(
                previousRuns: [],
                current: RunRecord(score: score, answered: score, date: Date(timeIntervalSince1970: 0))
            )
        )
    }

    @Test("home starts with an empty path")
    func startsAtHome() {
        #expect(AppRouter().path.isEmpty)
    }

    @Test("opening setup pushes one screen")
    func openSetup() {
        let router = AppRouter()
        router.openSetup(.revision)
        #expect(router.path == [.setup(.revision)])
    }

    @Test("results replaces the game, so Back never returns into a dead game")
    func resultsReplacesTheGame() {
        let router = AppRouter()
        router.openSetup(.countdown)
        router.startGame(.default)
        #expect(router.path == [.setup(.countdown), .game(.default)])

        router.showResults(summary(score: 9))
        #expect(router.path == [.results])
        #expect(router.summary?.score == 9)
    }

    @Test("playing again returns to the game with the same configuration")
    func playAgainReusesTheConfig() {
        let router = AppRouter()
        router.startGame(.default)
        router.showResults(summary(score: 3))
        router.playAgain()
        #expect(router.path == [.game(.default)])
    }

    @Test("playing again with no summary is a no-op rather than a crash")
    func playAgainWithoutSummary() {
        let router = AppRouter()
        router.playAgain()
        #expect(router.path.isEmpty)
    }

    @Test("going home clears the path and the stale summary")
    func goHomeClearsEverything() {
        let router = AppRouter()
        router.startGame(.default)
        router.showResults(summary(score: 4))
        router.goHome()
        #expect(router.path.isEmpty)
        #expect(router.summary == nil)
    }

    @Test("progress is reachable from home")
    func openProgress() {
        let router = AppRouter()
        router.openProgress()
        #expect(router.path == [.progress])
    }
}
```

`GameSession.Summary` must be `Equatable`-free but `summary` is optional-compared by field, so no conformance is needed. `Route` requires `Hashable`, which requires `GameConfig: Hashable` — already satisfied from Task 3.

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'AppRouter' in scope`.

- [ ] **Step 3: Create `Tables/Features/AppRouter.swift`**

```swift
import Foundation
import Observation

enum Route: Hashable {
    case setup(GameMode)
    case game(GameConfig)
    case results
    case progress
}

/// Owns navigation so no screen has to know what comes after it.
@MainActor
@Observable
final class AppRouter {
    var path: [Route] = []
    var isShowingSettings = false
    private(set) var summary: GameSession.Summary?

    func openSetup(_ mode: GameMode) {
        path.append(.setup(mode))
    }

    func startGame(_ config: GameConfig) {
        path.append(.game(config))
    }

    /// Replaces the stack rather than pushing, so Back from results goes home
    /// instead of re-entering a finished game.
    func showResults(_ summary: GameSession.Summary) {
        self.summary = summary
        path = [.results]
    }

    func playAgain() {
        guard let config = summary?.config else { return }
        path = [.game(config)]
    }

    func goHome() {
        summary = nil
        path = []
    }

    func openProgress() {
        path.append(.progress)
    }
}
```

- [ ] **Step 4: Create `Tables/Features/Home/HomeView.swift`**

```swift
import SwiftUI

/// Caps the content column on iPad. The design is drawn for a phone; a
/// stretched phone layout is not the same design.
struct PhoneColumn<Content: View>: View {
    @ViewBuilder private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content.frame(maxWidth: Metrics.contentMaxWidth)
            Spacer(minLength: 0)
        }
        .background(Color.canvas)
    }
}

struct HomeView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        PhoneColumn {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, Metrics.space7)

                Text("What do you want\nto practise?")
                    .font(Typography.display(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)

                Text("Test yourself against the clock, or take your time and revise.")
                    .font(Typography.ui(14.5, relativeTo: .subheadline))
                    .foregroundStyle(Color.inkSoft)
                    .lineSpacing(3)
                    .padding(.top, Metrics.space2)
                    .padding(.bottom, Metrics.space6)

                VStack(spacing: Metrics.space3 + 2) {
                    countdownCard
                    revisionCard
                }

                Spacer(minLength: Metrics.space5)

                progressRow
            }
            .padding(.horizontal, Metrics.space6 - 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space6)
        }
    }

    private var header: some View {
        HStack {
            BrandMark()
            Spacer()
            Button { router.isShowingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(Color.inkSoft)
                    .frame(width: Metrics.hitMin, height: Metrics.hitMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var countdownCard: some View {
        modeCard(
            eyebrow: "Beat the clock",
            title: "Countdown",
            body: "Answer as many as you can before the timer runs out.",
            tint: .skyTint,
            textColor: .skyText
        ) {
            Text("60")
                .font(Typography.display(44, relativeTo: .largeTitle))
                .foregroundStyle(Color.sky)
        } action: {
            router.openSetup(.countdown)
        }
    }

    private var revisionCard: some View {
        modeCard(
            eyebrow: "No timer",
            title: "Revision",
            body: "Practise the tables you find tricky without the pressure of a timer.",
            tint: .sageTint,
            textColor: .sageText
        ) {
            // Indices, not values — the opacities repeat, and duplicate ForEach
            // ids make SwiftUI drop views.
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 3), count: 2), spacing: 3) {
                ForEach(Array([1.0, 0.5, 0.5, 1.0].enumerated()), id: \.offset) { _, opacity in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.sage.opacity(opacity))
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 31)
        } action: {
            router.openSetup(.revision)
        }
    }

    private func modeCard<Motif: View>(
        eyebrow: String,
        title: String,
        body: String,
        tint: Color,
        textColor: Color,
        @ViewBuilder motif: () -> Motif,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Metrics.space3) {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(eyebrow, color: textColor.opacity(0.85))
                    Text(title)
                        .font(Typography.display(27, relativeTo: .title))
                        .foregroundStyle(textColor)
                        .padding(.top, 6)
                    Text(body)
                        .font(Typography.ui(13, relativeTo: .footnote))
                        .foregroundStyle(textColor.opacity(0.85))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 6)
                }
                Spacer(minLength: Metrics.space2)
                motif()
            }
            .padding(.vertical, Metrics.space5)
            .padding(.horizontal, Metrics.space4 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(body)")
    }

    private var progressRow: some View {
        Button { router.openProgress() } label: {
            HStack {
                Eyebrow("Progress")
                Spacer()
                HStack(spacing: Metrics.space1 + 2) {
                    Text("Your tables")
                    Image(systemName: "arrow.right")
                }
                .font(Typography.ui(13.5, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Color.skyText)
            }
            .padding(.top, Metrics.space5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

The `→` from the prototype is an SF Symbol here — the bundled Libre Franklin has no glyph for U+2192 and would silently fall back to the system face.

- [ ] **Step 5: Replace `Tables/TablesApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct TablesApp: App {
    @State private var router = AppRouter()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(settings)
                .tint(Color.skyText)
        }
        .modelContainer(for: [FactStat.self, GameRun.self])
    }
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.path) {
            HomeView()
                .navigationBarBackButtonHidden()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                        .navigationBarBackButtonHidden()
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .background(Color.canvas)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .setup(let mode):
            // Task 14 replaces this.
            PhoneColumn { Text(mode.title) }
        case .game(let config):
            // Task 15 replaces this.
            PhoneColumn { Text(config.summary) }
        case .results:
            // Task 17 replaces this.
            PhoneColumn { Text("Results") }
        case .progress:
            // Task 18 replaces this.
            PhoneColumn { Text("Your tables") }
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 7: Look at the home screen**

Build and run in the simulator:

```bash
xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -quiet
xcrun simctl boot "iPhone 17" 2>/dev/null; open -a Simulator
xcrun simctl install booted "$(xcodebuild -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/Tables.app"
xcrun simctl launch booted com.challengr.Tables
```

Confirm on screen: warm off-white background (not white), the tile triad and "Tables" set in a **slab serif** (if it looks like Times or SF, the font did not load), two pastel mode cards, and a gear top-right. Tapping a mode card pushes a placeholder screen.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add app shell, navigation and home screen

Router replaces the stack when a game finishes, so Back from results
goes home rather than into a dead game."
```

---

### Task 14: Setup screen

**Files:**
- Create: `Tables/Features/Setup/SetupView.swift`, `Tables/Features/Setup/SetupModel.swift`
- Modify: `Tables/TablesApp.swift` (replace the `.setup` placeholder)
- Test: `TablesTests/SetupModelTests.swift`

**Interfaces:**
- Consumes: `GameConfig`, `GameLength`, `AnswerMode` (Task 3), components (Task 12), `AppRouter` (Task 13).
- Produces:
  - `@MainActor @Observable final class SetupModel` with `init(mode: GameMode)`, `var tables: Set<Int>`, `var answerMode: AnswerMode`, `var length: GameLength`, `var openSection: Section?`, `enum Section { case tables, answerMode, length }`, and `func toggle(table:)`, `func toggleAll()`, `func toggle(section:)`, `var config: GameConfig`, `var allSelected: Bool`, `var selectAllLabel: String`, `var lengthOptions: [GameLength]`
  - `struct SetupView: View { init(mode: GameMode) }`

- [ ] **Step 1: Write the failing test**

Create `TablesTests/SetupModelTests.swift`:

```swift
import Testing
@testable import Tables

@MainActor
struct SetupModelTests {

    @Test("countdown opens on the tables section with sensible defaults")
    func countdownDefaults() {
        let model = SetupModel(mode: .countdown)
        #expect(model.openSection == .tables)
        #expect(model.tables == [3, 6, 7, 8])
        #expect(model.answerMode == .multipleChoice)
        #expect(model.length == .seconds(60))
        #expect(model.lengthOptions == GameLength.countdownOptions)
    }

    @Test("revision defaults to twenty questions")
    func revisionDefaults() {
        let model = SetupModel(mode: .revision)
        #expect(model.length == .questions(20))
        #expect(model.lengthOptions == GameLength.revisionOptions)
    }

    @Test("tapping a table toggles it in and out")
    func togglingTables() {
        let model = SetupModel(mode: .countdown)
        model.toggle(table: 5)
        #expect(model.tables.contains(5))
        model.toggle(table: 5)
        #expect(!model.tables.contains(5))
    }

    @Test("select all fills every table, then clears them")
    func selectAndClearAll() {
        let model = SetupModel(mode: .countdown)
        #expect(model.selectAllLabel == "Select all")

        model.toggleAll()
        #expect(model.tables == GameConfig.allTables)
        #expect(model.allSelected)
        #expect(model.selectAllLabel == "Clear all")

        model.toggleAll()
        #expect(model.tables.isEmpty)
        #expect(!model.config.isStartable)
    }

    @Test("only one section is open at a time, and tapping the open one closes it")
    func sectionsAreExclusive() {
        let model = SetupModel(mode: .countdown)
        model.toggle(section: .answerMode)
        #expect(model.openSection == .answerMode)
        model.toggle(section: .length)
        #expect(model.openSection == .length)
        model.toggle(section: .length)
        #expect(model.openSection == nil)
    }

    @Test("the model produces the config the game will be played with")
    func producesConfig() {
        let model = SetupModel(mode: .revision)
        model.tables = [2, 4]
        model.answerMode = .numberPad
        model.length = .endless

        #expect(model.config == GameConfig(
            mode: .revision, tables: [2, 4], answerMode: .numberPad, length: .endless
        ))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: FAIL — `cannot find 'SetupModel' in scope`.

- [ ] **Step 3: Create `Tables/Features/Setup/SetupModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SetupModel {
    enum Section: Hashable {
        case tables
        case answerMode
        case length
    }

    let mode: GameMode
    var tables: Set<Int>
    var answerMode: AnswerMode
    var length: GameLength
    var openSection: Section?

    init(mode: GameMode) {
        self.mode = mode
        self.tables = [3, 6, 7, 8]
        self.answerMode = .multipleChoice
        self.length = mode == .countdown ? .seconds(60) : .questions(20)
        self.openSection = .tables
    }

    var config: GameConfig {
        GameConfig(mode: mode, tables: tables, answerMode: answerMode, length: length)
    }

    var lengthOptions: [GameLength] {
        mode == .countdown ? GameLength.countdownOptions : GameLength.revisionOptions
    }

    var allSelected: Bool { tables == GameConfig.allTables }

    var selectAllLabel: String { allSelected ? "Clear all" : "Select all" }

    func toggle(table: Int) {
        if tables.contains(table) {
            tables.remove(table)
        } else {
            tables.insert(table)
        }
    }

    func toggleAll() {
        tables = allSelected ? [] : GameConfig.allTables
    }

    func toggle(section: Section) {
        openSection = openSection == section ? nil : section
    }
}
```

- [ ] **Step 4: Create `Tables/Features/Setup/SetupView.swift`**

```swift
import SwiftUI

struct SetupView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SetupModel

    init(mode: GameMode) {
        _model = State(initialValue: SetupModel(mode: mode))
    }

    var body: some View {
        PhoneColumn {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.space3 + 2) {
                    BackButton { router.goHome() }
                    Text(model.mode.title)
                        .font(Typography.display(27, relativeTo: .title))
                        .foregroundStyle(Color.ink)
                }
                .padding(.bottom, Metrics.space4 + 2)

                ScrollView {
                    VStack(spacing: Metrics.space2 + 2) {
                        tablesSection
                        answerModeSection
                        lengthSection
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                PillButton(
                    "Start \(model.mode.lowercasedTitle)",
                    isEnabled: model.config.isStartable
                ) {
                    router.startGame(model.config)
                }
                .padding(.top, Metrics.space3 + 2)
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space5)
        }
        .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: model.openSection)
    }

    private func section<Content: View>(
        _ id: SetupModel.Section,
        label: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Button { model.toggle(section: id) } label: {
                    HStack {
                        Eyebrow(label)
                        Spacer(minLength: Metrics.space3)
                        Text(summary)
                            .font(Typography.ui(13, relativeTo: .footnote))
                            .foregroundStyle(Color.inkSoft)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(Metrics.space4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if model.openSection == id {
                    content()
                        .padding(.horizontal, Metrics.space4)
                        .padding(.bottom, Metrics.space4)
                }
            }
        }
    }

    private var tablesSection: some View {
        section(.tables, label: "Tables", summary: model.config.tablesSummary) {
            VStack(spacing: Metrics.space2 + 2) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.space2), count: 4),
                    spacing: Metrics.space2
                ) {
                    ForEach(1...12, id: \.self) { number in
                        TileButton(
                            label: "\(number)",
                            state: model.tables.contains(number) ? .selected : .neutral,
                            font: Typography.display(20, relativeTo: .title3),
                            verticalPadding: Metrics.space3
                        ) {
                            model.toggle(table: number)
                        }
                        .accessibilityLabel("\(number) times table")
                        .accessibilityAddTraits(model.tables.contains(number) ? .isSelected : [])
                    }
                }

                Button { model.toggleAll() } label: {
                    Text(model.selectAllLabel)
                        .font(Typography.ui(13, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Color.skyText)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var answerModeSection: some View {
        section(.answerMode, label: "Answer mode", summary: model.answerMode.title) {
            VStack(spacing: Metrics.space2) {
                ForEach(AnswerMode.allCases, id: \.self) { mode in
                    answerRow(mode)
                }
                voiceRow
            }
        }
    }

    private func answerRow(_ mode: AnswerMode) -> some View {
        let isSelected = model.answerMode == mode
        return Button { model.answerMode = mode } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(mode.title)
                        .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Color.ink)
                    Text(mode.subtitle)
                        .font(Typography.ui(12, relativeTo: .caption))
                        .foregroundStyle(Color.inkSoft)
                }
                Spacer()
                radioDot(isSelected: isSelected)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, Metrics.space3 + 2)
            .background(isSelected ? Color.skyTint : Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                    .strokeBorder(isSelected ? Color.sky : Color.border, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func radioDot(isSelected: Bool) -> some View {
        Circle()
            .fill(isSelected ? Color.sky : Color.clear)
            .frame(width: 20, height: 20)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.skyTint : Color.line, lineWidth: isSelected ? 5 : 1.5)
            }
            .overlay {
                if isSelected { Circle().strokeBorder(Color.sky, lineWidth: 1.5) }
            }
    }

    private var voiceRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Voice")
                    .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Color.inkSoft)
                Text("Say it out loud")
                    .font(Typography.ui(12, relativeTo: .caption))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer()
            StatusChip("Soon")
        }
        .padding(.vertical, 13)
        .padding(.horizontal, Metrics.space3 + 2)
        .background(Color.tileNeutral)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                .strokeBorder(Color.border, lineWidth: 1.5)
        }
        .opacity(0.75)
        .accessibilityLabel("Voice. Say it out loud. Coming soon.")
    }

    private var lengthSection: some View {
        section(.length, label: model.mode.lengthSectionLabel, summary: model.length.summary) {
            FlowRow(spacing: Metrics.space2) {
                ForEach(model.lengthOptions, id: \.self) { option in
                    Chip(option.chipLabel, isSelected: model.length == option) {
                        model.length = option
                    }
                }
            }
        }
    }
}

/// Wraps chips onto as many rows as they need.
struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: width, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 5: Wire it into the router**

In `Tables/TablesApp.swift`, replace the `.setup` case:

```swift
        case .setup(let mode):
            SetupView(mode: mode)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 7: Look at the setup screen**

Launch the app (commands as in Task 13 Step 7) and tap Countdown. Confirm: only one section is open at a time; the collapsed rows show a live summary on the right; tapping tables toggles them to sky-tinted with a 2pt sky border; "Clear all" then disables the Start button; the Voice row is greyed with a lilac "Soon" pill and does nothing when tapped. Tap Revision and confirm the third section reads "Length" with an "Endless" chip.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add setup screen

Three exclusive accordion sections for tables, answer mode and length,
with a Start button that stays disabled until a table is chosen."
```

---

### Task 15: Game screen and multiple choice

**Files:**
- Create: `Tables/Features/Game/GameView.swift`, `Tables/Features/Game/MultipleChoiceView.swift`
- Modify: `Tables/TablesApp.swift` (replace the `.game` placeholder)
- Test: none new (all behaviour is covered by `GameSessionTests`)

**Interfaces:**
- Consumes: `GameSession` (Task 11), components (Task 12), `AppRouter` (Task 13), `AppSettings` (Task 10).
- Produces:
  - `struct GameView: View { init(config: GameConfig) }`
  - `struct MultipleChoiceView: View { init(session: GameSession) }`
  - `func tileState(for value: Int, in session: GameSession) -> TileState` on `MultipleChoiceView`

- [ ] **Step 1: Create `Tables/Features/Game/MultipleChoiceView.swift`**

```swift
import SwiftUI

struct MultipleChoiceView: View {
    let session: GameSession

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Metrics.space3), count: 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.space3) {
            ForEach(session.options, id: \.self) { value in
                TileButton(
                    label: "\(value)",
                    state: state(for: value),
                    font: Typography.display(26, relativeTo: .title2)
                ) {
                    session.submit(value, now: Date())
                }
                .accessibilityLabel("\(value)")
            }
        }
    }

    /// The tapped tile turns sage or blush. In Revision the correct tile also
    /// turns sage, so a wrong answer still teaches the right one.
    private func state(for value: Int) -> TileState {
        guard let picked = session.pickedValue else { return .neutral }
        if value == picked {
            return value == session.fact.answer ? .correct : .incorrect
        }
        if session.revealAnswer && value == session.fact.answer {
            return .correct
        }
        return .neutral
    }
}
```

- [ ] **Step 2: Create `Tables/Features/Game/GameView.swift`**

`import Combine` is required — `Timer.publish` and `.onReceive` come from Combine, not Foundation.

```swift
import SwiftUI
import Combine

struct GameView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let config: GameConfig
    @State private var session: GameSession?

    init(config: GameConfig) {
        self.config = config
    }

    var body: some View {
        PhoneColumn {
            VStack(spacing: 0) {
                if let session {
                    header(session)
                    content(session)
                    PillButton(session.endLabel, style: .ghost) {
                        if session.endEarly(now: Date()) == .finished {
                            if let summary = session.summary { router.showResults(summary) }
                        } else {
                            router.goHome()
                        }
                    }
                    .padding(.bottom, Metrics.space3 + 2)
                } else {
                    Color.canvas
                }
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space2)
            .padding(.bottom, Metrics.space5)
        }
        .onAppear(perform: startIfNeeded)
        .onChange(of: scenePhase) { _, phase in
            guard let session else { return }
            if phase == .active { session.resume(now: Date()) } else { session.pause(now: Date()) }
        }
        // 20Hz is enough for a whole-second clock and a 240ms cross-fade, and
        // cheap enough not to matter.
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { now in
            guard let session, session.phase != .finished else { return }
            session.tick(now: now)
            if session.phase == .finished, let summary = session.summary {
                router.showResults(summary)
            }
        }
    }

    private func startIfNeeded() {
        guard session == nil else { return }
        let player = FeedbackPlayer(settings: settings)
        // Warming the haptic generators here keeps the first tap as crisp as
        // the rest.
        player.prepare()
        let created = GameSession(
            config: config,
            store: SwiftDataProgressStore(context: modelContext),
            optionCount: settings.multipleChoiceOptionCount,
            feedback: player,
            rng: SystemRandomNumberGenerator()
        )
        created.start(now: Date())
        session = created
    }

    private func header(_ session: GameSession) -> some View {
        HStack {
            BackButton { router.goHome() }
            Spacer()
            Eyebrow(config.mode.title)
            Spacer()
            statusPill(session)
        }
        .padding(.bottom, Metrics.space1 + 2)
    }

    @ViewBuilder
    private func statusPill(_ session: GameSession) -> some View {
        let isCountdown = config.mode == .countdown
        let text = isCountdown ? session.timeText : session.revisionProgressText
        let isLow = isCountdown && session.isLowTime

        Text(text)
            .font(Typography.display(19, relativeTo: .headline))
            .foregroundStyle(isLow ? Color.blushText : Color.skyText)
            .monospacedDigit()
            .padding(.vertical, Metrics.space2)
            .padding(.horizontal, isCountdown ? Metrics.space4 + 2 : Metrics.space4)
            .background(isLow ? Color.blush : Color.skyTint)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard, style: .continuous))
            .animation(Motion.animation(Motion.fadeAnimation, reduceMotion: reduceMotion), value: isLow)
            .frame(minWidth: 64)
            .accessibilityLabel(isCountdown ? "\(session.secondsRemaining) seconds left" : "\(session.answered) answered")
    }

    private func content(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: Metrics.space4)

            Text(session.fact.display)
                .font(Typography.display(config.answerMode == .multipleChoice ? 56 : 52, relativeTo: .largeTitle))
                .foregroundStyle(Color.ink)
                .opacity(session.isFadingOut ? 0 : 1)
                .animation(
                    Motion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
                    value: session.isFadingOut
                )

            // Reserved space, so nothing shifts when feedback appears.
            feedbackPill(session)
                .frame(height: 34)
                .padding(.top, Metrics.space3)

            Spacer(minLength: Metrics.space4)

            Group {
                switch config.answerMode {
                case .multipleChoice:
                    MultipleChoiceView(session: session)
                case .numberPad:
                    NumberPadView(session: session)
                }
            }
            .opacity(session.isFadingOut ? 0 : 1)
            .animation(
                Motion.animation(.easeInOut(duration: 0.22), reduceMotion: reduceMotion),
                value: session.isFadingOut
            )

            Spacer(minLength: Metrics.space4)
        }
    }

    @ViewBuilder
    private func feedbackPill(_ session: GameSession) -> some View {
        if case .feedback(let isCorrect, let text) = session.phase {
            Text(text)
                .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isCorrect ? Color.sageText : Color.blushText)
                .padding(.vertical, 7)
                .padding(.horizontal, Metrics.space4)
                .background(isCorrect ? Color.sageTint : Color.blushTint)
                .clipShape(Capsule())
                .transition(.opacity)
        } else {
            Color.clear
        }
    }
}
```

`NumberPadView` does not exist until Task 16. To keep the build green, add a temporary stub at the bottom of `GameView.swift` and delete it in Task 16:

```swift
// Replaced by Task 16.
struct NumberPadView: View {
    let session: GameSession
    var body: some View { Color.clear }
}
```

- [ ] **Step 3: Wire it into the router**

In `Tables/TablesApp.swift`, replace the `.game` case:

```swift
        case .game(let config):
            GameView(config: config)
```

- [ ] **Step 4: Verify the build and the existing tests still pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 5: Play a game**

Launch and start a 30-second Countdown with multiple choice. Confirm: the timer counts down and turns blush in the last 10 seconds; a correct tap turns the tile sage and pops once; a wrong tap turns it blush and the **same question stays**; the problem cross-fades to the next question; backgrounding the app (Cmd-Shift-H in the simulator) and returning does not lose time. Let the clock run out and confirm it lands on the Results placeholder.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add game screen and multiple choice

Timer, feedback pill in reserved space, cross-fade between questions,
and pause on backgrounding."
```

---

### Task 16: Number pad

**Files:**
- Create: `Tables/Features/Game/NumberPadView.swift`
- Modify: `Tables/Features/Game/GameView.swift` (delete the stub added in Task 15)
- Test: none new (pad editing is covered by `GameSessionTests`)

**Interfaces:**
- Consumes: `GameSession` (Task 11), components (Task 12).
- Produces: `struct NumberPadView: View { let session: GameSession }`

- [ ] **Step 1: Delete the stub**

Remove the temporary `NumberPadView` from the bottom of `Tables/Features/Game/GameView.swift`.

- [ ] **Step 2: Create `Tables/Features/Game/NumberPadView.swift`**

```swift
import SwiftUI

/// A custom pad, never the system keyboard — the app's typography and spacing
/// have to hold all the way through the game.
struct NumberPadView: View {
    let session: GameSession

    private enum Key: Hashable {
        case digit(Int)
        case delete
        case submit
    }

    private static let keys: [Key] = [
        .digit(1), .digit(2), .digit(3),
        .digit(4), .digit(5), .digit(6),
        .digit(7), .digit(8), .digit(9),
        .delete, .digit(0), .submit
    ]

    private var displayBorder: Color {
        switch session.phase {
        case .feedback(let isCorrect, _): isCorrect ? .sage : .blush
        default: .line
        }
    }

    var body: some View {
        VStack(spacing: Metrics.space3 + 2) {
            entryDisplay

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.space2 + 2), count: 3),
                spacing: Metrics.space2 + 2
            ) {
                ForEach(Self.keys, id: \.self) { key in
                    keyButton(key)
                }
            }
        }
    }

    private var entryDisplay: some View {
        Text(session.padValue.isEmpty ? " " : session.padValue)
            .font(Typography.display(34, relativeTo: .largeTitle))
            .foregroundStyle(Color.ink)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                    .strokeBorder(displayBorder, lineWidth: Metrics.strokeTile)
            }
            .accessibilityLabel(session.padValue.isEmpty ? "No answer entered" : "Answer \(session.padValue)")
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        Button {
            switch key {
            case .digit(let value): session.padAppend(value)
            case .delete: session.padDelete()
            case .submit: session.padSubmit(now: Date())
            }
        } label: {
            label(for: key)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(background(for: key))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusKey, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.radiusKey, style: .continuous)
                        .strokeBorder(stroke(for: key), lineWidth: Metrics.strokeTile)
                }
        }
        .buttonStyle(.plain)
        .disabled(key == .submit && !session.canSubmitPad)
        .opacity(key == .submit && !session.canSubmitPad ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel(for: key))
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case .digit(let value):
            Text("\(value)")
                .font(Typography.display(24, relativeTo: .title2))
                .foregroundStyle(Color.ink)
        case .delete:
            // The bundled fonts have no glyph for ⌫, so this is an SF Symbol.
            Image(systemName: "delete.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.inkSoft)
        case .submit:
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.paper)
        }
    }

    private func background(for key: Key) -> Color {
        switch key {
        case .digit: .paper
        case .delete: .tileNeutral
        case .submit: .ink
        }
    }

    private func stroke(for key: Key) -> Color {
        switch key {
        case .digit: .line
        case .delete: .border
        case .submit: .ink
        }
    }

    private func accessibilityLabel(for key: Key) -> String {
        switch key {
        case .digit(let value): "\(value)"
        case .delete: "Delete"
        case .submit: "Submit answer"
        }
    }
}
```

- [ ] **Step 3: Verify the build and tests**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 4: Play a number-pad game**

Start a Revision session with Number pad. Confirm: the system keyboard never appears; digits fill the display and stop at three; delete removes one; the submit key is dimmed until a value is entered; a wrong answer reveals the full fact ("7 × 8 = 56") and moves on; the display border turns sage or blush with the answer.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add custom number pad

Delete and submit use SF Symbols, since the bundled fonts have no glyph
for the characters the prototype set as text."
```

---

### Task 17: Results screen

**Files:**
- Create: `Tables/Features/Results/ResultsView.swift`
- Modify: `Tables/TablesApp.swift` (replace the `.results` placeholder)
- Test: none new (`ScoreBoardTests` covers the ranking and banner copy)

**Interfaces:**
- Consumes: `GameSession.Summary`, `ScoreBoard` (Tasks 7, 11), `AppRouter` (Task 13).
- Produces: `struct ResultsView: View { let summary: GameSession.Summary }`

- [ ] **Step 1: Create `Tables/Features/Results/ResultsView.swift`**

```swift
import SwiftUI

struct ResultsView: View {
    @Environment(AppRouter.self) private var router

    let summary: GameSession.Summary

    private var now: Date { Date() }

    private var unit: String {
        summary.config.mode == .countdown ? "correct answers" : "answered correctly"
    }

    var body: some View {
        PhoneColumn {
            VStack(spacing: 0) {
                Eyebrow(summary.config.summary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 6) {
                    Text("\(summary.score)")
                        .font(Typography.display(80, relativeTo: .largeTitle))
                        .foregroundStyle(Color.ink)
                    Text(unit)
                        .font(Typography.ui(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.inkSoft)
                }
                .padding(.top, Metrics.space5)
                .padding(.bottom, Metrics.space4)
                .accessibilityElement(children: .combine)

                banner

                Eyebrow("Your best runs")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Metrics.space5)
                    .padding(.bottom, Metrics.space2 + 2)

                ScrollView {
                    VStack(spacing: Metrics.space1 + 2) {
                        ForEach(Array(summary.board.topRuns.enumerated()), id: \.element.date) { index, run in
                            row(rank: index + 1, run: run)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: Metrics.space2 + 2) {
                    PillButton("Play again") { router.playAgain() }
                    PillButton("Back home", style: .ghost) { router.goHome() }
                }
                .padding(.top, Metrics.space3 + 2)
            }
            .padding(.horizontal, Metrics.space5 + 2)
            .padding(.top, Metrics.space3 + 2)
            .padding(.bottom, Metrics.space5)
        }
    }

    private var banner: some View {
        Text(summary.board.bannerText)
            .font(Typography.ui(13.5, weight: .semibold, relativeTo: .footnote))
            .foregroundStyle(summary.board.isNewBest ? Color.sageText : Color.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Metrics.space2 + 2)
            .padding(.horizontal, Metrics.space4)
            .background(summary.board.isNewBest ? Color.sageTint : Color.tileNeutral)
            .clipShape(Capsule())
    }

    private func row(rank: Int, run: RunRecord) -> some View {
        let isCurrent = run == summary.board.current

        return HStack(spacing: Metrics.space3 + 2) {
            Text("\(rank)")
                .font(Typography.display(15, relativeTo: .subheadline))
                .foregroundStyle(isCurrent ? Color.sageText : Color.inkMuted)
                .frame(width: 16, alignment: .leading)

            Text(ScoreBoard.relativeDateLabel(for: run.date, isCurrentRun: isCurrent, now: now))
                .font(Typography.ui(13, relativeTo: .footnote))
                .foregroundStyle(isCurrent ? Color.sageText : Color.ink)

            Spacer()

            Text("\(run.score)")
                .font(Typography.display(20, relativeTo: .title3))
                .foregroundStyle(isCurrent ? Color.sageText : Color.ink)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Metrics.space3 + 2)
        .background(isCurrent ? Color.sage : Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous))
        .overlay {
            if !isCurrent {
                RoundedRectangle(cornerRadius: Metrics.radiusCard - 2, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: Metrics.strokeCard)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: Wire it into the router**

In `Tables/TablesApp.swift`, replace the `.results` case:

```swift
        case .results:
            if let summary = router.summary {
                ResultsView(summary: summary)
            } else {
                // Only reachable if the stack is restored without a summary.
                PhoneColumn { Color.canvas }
                    .onAppear { router.goHome() }
            }
```

- [ ] **Step 3: Verify the build and tests**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 4: Look at the results screen**

Play a 30-second Countdown to completion. Confirm: the eyebrow reads the exact configuration; the score is large and slab-set; the first ever run scoring above zero says "New personal best"; the run just played is highlighted sage in the list and labelled "Just now". Play a second, worse run and confirm the banner reads "Your best is N" and the highlighted row moves down the list. Then change the time limit and confirm the board is empty except for that run — scores are scoped per configuration.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add results screen

Score, comparison banner and the top five runs for that exact
configuration, with the just-played run highlighted."
```

---

### Task 18: Progress screen

**Files:**
- Create: `Tables/Features/Progress/MasteryGridView.swift`
- Modify: `Tables/TablesApp.swift` (replace the `.progress` placeholder)
- Test: none new (`MasteryTests` and `ProgressStoreTests` cover the levels)

**Interfaces:**
- Consumes: `Mastery`, `MasteryLevel` (Task 5), `SwiftDataProgressStore` (Task 9), `AppRouter` (Task 13).
- Produces:
  - `struct MasteryGridView: View`
  - `extension MasteryLevel { var fill: Color; var needsOutline: Bool }`

- [ ] **Step 1: Create `Tables/Features/Progress/MasteryGridView.swift`**

```swift
import SwiftUI
import SwiftData

extension MasteryLevel {
    var fill: Color {
        switch self {
        case .mastered: .sage
        case .gettingThere: .butter
        case .notYet: .tileNeutral
        }
    }

    /// Only the empty state needs an outline to read as a cell at all.
    var needsOutline: Bool { self == .notYet }
}

struct MasteryGridView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query private var stats: [FactStat]

    private var levels: [String: MasteryLevel] {
        Dictionary(uniqueKeysWithValues: stats.map { ($0.key, Mastery.level(for: $0.history)) })
    }

    var body: some View {
        PhoneColumn {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Metrics.space3 + 2) {
                        BackButton { router.goHome() }
                        Text("Your tables")
                            .font(Typography.display(27, relativeTo: .title))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.bottom, Metrics.space2 + 2)

                    Text("Track your progress and see which tables to revise. How many can you master?")
                        .font(Typography.ui(14, relativeTo: .subheadline))
                        .foregroundStyle(Color.inkSoft)
                        .lineSpacing(3)
                        .padding(.bottom, Metrics.space4 + 2)

                    Card {
                        VStack(alignment: .leading, spacing: Metrics.space3 + 2) {
                            legend
                            grid
                        }
                        .padding(Metrics.space4)
                    }
                }
                .padding(.horizontal, Metrics.space5 + 2)
                .padding(.top, Metrics.space2)
                .padding(.bottom, Metrics.space6)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Metrics.space3 + 2) {
            ForEach([MasteryLevel.mastered, .gettingThere, .notYet], id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(level.fill)
                        .frame(width: 12, height: 12)
                        .overlay {
                            if level.needsOutline {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color.line, lineWidth: 1)
                            }
                        }
                    Text(level.legendLabel)
                        .font(Typography.ui(12, relativeTo: .caption))
                        .foregroundStyle(Color.inkSoft)
                }
            }
        }
    }

    private var grid: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Color.clear.frame(width: 14, height: 1)
                ForEach(1...12, id: \.self) { column in
                    axisLabel("\(column)", color: .inkMuted)
                }
            }
            ForEach(1...12, id: \.self) { row in
                GridRow {
                    axisLabel("\(row)", color: .inkSoft)
                    ForEach(1...12, id: \.self) { column in
                        cell(a: row, b: column)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func axisLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Typography.ui(9, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
    }

    private func cell(a: Int, b: Int) -> some View {
        let level = levels[Fact(a: a, b: b).key] ?? .notYet
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(level.fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if level.needsOutline {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.line, lineWidth: 1)
                }
            }
    }

    /// The grid is 144 cells; reading it out one by one would be useless.
    private var accessibilitySummary: String {
        let all = levels.values
        let mastered = all.filter { $0 == .mastered }.count
        let gettingThere = all.filter { $0 == .gettingThere }.count
        return "Mastery grid. \(mastered) of 144 facts mastered, \(gettingThere) getting there."
    }
}
```

There is no demo data and no fallback pattern. A child who has answered nothing sees an empty grid, because inventing progress they have not earned would be a lie.

- [ ] **Step 2: Wire it into the router**

In `Tables/TablesApp.swift`, replace the `.progress` case:

```swift
        case .progress:
            MasteryGridView()
```

- [ ] **Step 3: Verify the build and tests**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 4: Look at the progress screen**

Delete the app from the simulator first (`xcrun simctl uninstall booted com.challengr.Tables`) so the store is empty, then relaunch and open Progress. Confirm the grid is entirely "Not yet" — no invented pattern. Play a Revision session on ×3 answering quickly and correctly, then reopen Progress and confirm the ×3 row starts turning butter and then sage.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add progress screen

A 12 by 12 mastery grid driven by real answering history, with no demo
data and no invented progress."
```

---

### Task 19: Settings sheet

**Files:**
- Create: `Tables/Features/Settings/SettingsView.swift`
- Modify: `Tables/Features/Home/HomeView.swift` (present the sheet)
- Test: none new (`AppSettingsTests` covers persistence)

**Interfaces:**
- Consumes: `AppSettings` (Task 10), `AppRouter` (Task 13), components (Task 12).
- Produces: `struct SettingsView: View`

- [ ] **Step 1: Create `Tables/Features/Settings/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ZStack {
                Color.canvas.ignoresSafeArea()

                VStack(spacing: Metrics.space2 + 2) {
                    Card {
                        VStack(spacing: 0) {
                            toggleRow("Sound", isOn: $settings.soundEnabled)
                            Divider().overlay(Color.divider)
                            toggleRow("Haptics", isOn: $settings.hapticsEnabled)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Metrics.space3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multiple choice options")
                                    .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                                    .foregroundStyle(Color.ink)
                                Text("How many tiles to choose between.")
                                    .font(Typography.ui(12, relativeTo: .caption))
                                    .foregroundStyle(Color.inkSoft)
                            }

                            HStack(spacing: Metrics.space2) {
                                ForEach(AppSettings.optionCountChoices, id: \.self) { count in
                                    Chip(
                                        "\(count)",
                                        isSelected: settings.multipleChoiceOptionCount == count
                                    ) {
                                        settings.multipleChoiceOptionCount = count
                                    }
                                }
                            }
                        }
                        .padding(Metrics.space4)
                    }

                    Spacer()
                }
                .padding(.horizontal, Metrics.space5 + 2)
                .padding(.top, Metrics.space5)
                .frame(maxWidth: Metrics.contentMaxWidth)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Typography.ui(16, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(Color.skyText)
                }
            }
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
        }
        .tint(Color.sage)
        .padding(Metrics.space4)
    }
}
```

The settings sheet deliberately holds three controls and nothing else. The prototype's `showFeedback` and `lowTimeWarning` props are always on — they are part of how the game reads, not preferences.

- [ ] **Step 2: Present it from Home**

In `Tables/Features/Home/HomeView.swift`, add to the outermost `PhoneColumn`:

```swift
        .sheet(isPresented: Binding(
            get: { router.isShowingSettings },
            set: { router.isShowingSettings = $0 }
        )) {
            SettingsView()
        }
```

- [ ] **Step 3: Verify the build and tests**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests -quiet 2>&1 | tail -20`

Expected: PASS.

- [ ] **Step 4: Check the settings actually take effect**

Open Settings from the gear, set multiple choice options to 4, and Done. Start a Countdown with multiple choice and confirm four tiles in a 2×2 grid. Turn Sound off and confirm answers are silent; turn Haptics off and confirm no tap is felt (on a device — the simulator has no haptics). Force-quit and relaunch, and confirm all three settings held.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Add settings sheet

Sound, haptics and multiple-choice option count, reachable from the gear
on the home screen."
```

---

### Task 20: UI smoke test and final verification

**Files:**
- Create: `TablesUITests/GameFlowUITests.swift`
- Delete: `TablesUITests/TablesUITests.swift`
- Modify: `Tables/Features/Home/HomeView.swift`, `SetupView.swift`, `GameView.swift`, `ResultsView.swift` (add accessibility identifiers)

**Interfaces:**
- Consumes: the whole app.
- Produces: a smoke test covering launch → Countdown → Start → answer → Results.

- [ ] **Step 1: Add accessibility identifiers**

The UI test needs stable handles. Add `.accessibilityIdentifier(_:)` to these views:

| View | Element | Identifier |
|---|---|---|
| `HomeView` | Countdown mode card button | `home.countdown` |
| `HomeView` | Revision mode card button | `home.revision` |
| `HomeView` | Progress row button | `home.progress` |
| `HomeView` | Settings gear button | `home.settings` |
| `SetupView` | Start button | `setup.start` |
| `SetupView` | Each table tile | `setup.table.\(number)` |
| `GameView` | The problem `Text` | `game.problem` |
| `GameView` | Status pill | `game.status` |
| `GameView` | End/Finish button | `game.end` |
| `MultipleChoiceView` | Each option tile | `game.option.\(value)` |
| `ResultsView` | Score `Text` | `results.score` |
| `ResultsView` | Play again button | `results.playAgain` |

`PillButton` and `TileButton` need to forward an identifier, so add an optional `identifier: String? = nil` parameter to each and apply `.accessibilityIdentifier(identifier ?? "")` when non-nil.

- [ ] **Step 2: Write the UI smoke test**

```bash
rm TablesUITests/TablesUITests.swift
```

Create `TablesUITests/GameFlowUITests.swift`:

```swift
import XCTest

final class GameFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testCountdownGameReachesResults() throws {
        // Home
        let countdown = app.buttons["home.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 10))
        countdown.tap()

        // Setup: a single table and the shortest run keeps the test quick.
        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Game
        let problem = app.staticTexts["game.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 5))
        XCTAssertTrue(problem.label.contains("\u{00D7}"), "the problem should use ×, got \(problem.label)")
        XCTAssertTrue(app.staticTexts["game.status"].exists)

        // End the run early rather than waiting out the clock.
        let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'game.option.'")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()

        let end = app.buttons["game.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()

        // Results
        XCTAssertTrue(app.staticTexts["results.score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["results.playAgain"].exists)
    }

    func testProgressScreenOpensFromHome() throws {
        let progress = app.buttons["home.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        progress.tap()
        XCTAssertTrue(app.staticTexts["Your tables"].waitForExistence(timeout: 5))
    }

    func testSettingsSheetOpensAndCloses() throws {
        let gear = app.buttons["home.settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
    }
}
```

Also delete the template launch test's screenshot boilerplate but keep the file:

`TablesUITests/TablesUITestsLaunchTests.swift` stays as-is — a launch check is worth having.

- [ ] **Step 3: Run the full suite**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -quiet 2>&1 | tail -30`

Expected: PASS — all `TablesTests` and all `TablesUITests`. UI tests take around a minute.

- [ ] **Step 4: Check the iPad layout**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:TablesUITests -quiet 2>&1 | tail -20`

If that simulator is unavailable, pick another iPad from `xcrun simctl list devices available`. Then launch the app on the iPad simulator and confirm: the content sits in a centred column rather than stretching edge to edge, and rotating the device does not change the orientation.

- [ ] **Step 5: Confirm the spec is met**

Walk the spec's section 12 and check each in-scope item works in the running app:

- Countdown at 30, 60, 90 and 120 seconds
- Revision at 10 through 60 questions and Endless
- Tables 1–12, multi-select, Select all / Clear all
- Multiple choice at 4 and 6 options, number pad
- Voice shown as "Soon" and not selectable
- Wrong answer retries in Countdown, reveals in Revision
- Best runs scoped per exact configuration
- Mastery grid reflecting real play
- Sound, haptics and option count persisting across launches
- No emoji anywhere; `×` throughout
- Portrait only, light appearance, on both iPhone and iPad

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Add UI smoke tests and accessibility identifiers

Covers launch to results, the progress screen and the settings sheet."
```

---

## Done

At this point the app builds, all unit and UI tests pass, and every in-scope
item in the spec is implemented. Out of scope by design: voice input, dark
mode, landscape, and any operation other than multiplication.
