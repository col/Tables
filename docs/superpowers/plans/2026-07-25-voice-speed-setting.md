# Adjustable Voice Speed Setting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 5-notch "Voice speed" slider to Settings that tunes the voice controller's two settle durations (short + on-track), replacing today's hardcoded constants.

**Architecture:** A pure `VoiceSpeed` enum holds the durations per notch. `AppSettings` persists the chosen speed. `SettingsView` renders a native 5-step slider (only when voice is supported). `VoiceAnswerController` takes a `VoiceSpeed` and reads its durations; `VoiceInputView` passes `settings.voiceSpeed` in. `GameSession` and the recognizer are unchanged.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `Duration`, Swift Testing.

## Global Constraints

- App target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; pure Sendable value types are `nonisolated` (as `AnswerMode`, `SpokenNumber`, `VoiceProgress`). UI/controller types are `@MainActor`.
- Values (short wait / on-track wait): Fastest 200/600, Fast 300/700, Normal 400/800, Slow 500/900, Slowest 600/1000. Default `.normal`.
- Mapping rule unchanged: `.onTrack → onTrackWait`; `.matches` / `.offTrack → shortWait`; terminal number submits immediately.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`), `@MainActor struct` where they touch main-actor types. `AppSettingsTests` uses a `freshDefaults(_:)` helper (a wiped `UserDefaults(suiteName:)`). Seeded RNG `SeededRandom(seed:)`; feedback double `SilentFeedbackPlayer`.
- `GameSession`, `SpeechAnswerRecognizer`, and `SpokenNumberParser` are not modified.

**Test command** (substitute an installed simulator if `iPhone 17` isn't present — `xcrun simctl list devices available`; the booted `iPhone 16e` id `29F3A533-0683-4506-8440-68F304640F68` also works):
```bash
xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/<SuiteName>
```
**Build-only:**
```bash
xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'
```
Run xcodebuild in the FOREGROUND (single blocking call); do not poll with a background Monitor.

---

### Task 1: `VoiceSpeed` type

**Files:**
- Create: `Tables/Model/VoiceSpeed.swift`
- Test: `TablesTests/VoiceSpeedTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum VoiceSpeed: Int, CaseIterable, Codable, Sendable { case fastest, fast, normal, slow, slowest; var label: String; var shortWait: Duration; var onTrackWait: Duration }`.

- [ ] **Step 1: Write the failing test**

`TablesTests/VoiceSpeedTests.swift`:
```swift
import Testing
@testable import Tables

struct VoiceSpeedTests {

    @Test("cases are ordered fastest to slowest by raw value")
    func order() {
        #expect(VoiceSpeed.allCases == [.fastest, .fast, .normal, .slow, .slowest])
        #expect(VoiceSpeed.fastest.rawValue == 0)
        #expect(VoiceSpeed.slowest.rawValue == 4)
    }

    @Test("durations and labels match the table", arguments: [
        (VoiceSpeed.fastest, "Fastest", 200, 600),
        (.fast, "Fast", 300, 700),
        (.normal, "Normal", 400, 800),
        (.slow, "Slow", 500, 900),
        (.slowest, "Slowest", 600, 1000),
    ])
    func table(speed: VoiceSpeed, label: String, short: Int, onTrack: Int) {
        #expect(speed.label == label)
        #expect(speed.shortWait == .milliseconds(short))
        #expect(speed.onTrackWait == .milliseconds(onTrack))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceSpeedTests`
Expected: FAIL — `VoiceSpeed` undefined.

- [ ] **Step 3: Write the implementation**

`Tables/Model/VoiceSpeed.swift`:
```swift
import Foundation

/// How eagerly voice recognition submits an answer, chosen on the settings
/// slider. Each notch sets the two settle durations the voice controller uses.
///
/// `Int`-backed so it maps directly onto a 5-step slider and persists as a small
/// integer. `nonisolated`: a pure Sendable value type (see `SpokenNumber`).
nonisolated enum VoiceSpeed: Int, CaseIterable, Codable, Sendable {
    case fastest, fast, normal, slow, slowest

    var label: String {
        switch self {
        case .fastest: "Fastest"
        case .fast: "Fast"
        case .normal: "Normal"
        case .slow: "Slow"
        case .slowest: "Slowest"
        }
    }

    /// Wait for a match or an off-track number — already decided, this is just a
    /// short insurance window in case it grows into a different number.
    var shortWait: Duration {
        switch self {
        case .fastest: .milliseconds(200)
        case .fast: .milliseconds(300)
        case .normal: .milliseconds(400)
        case .slow: .milliseconds(500)
        case .slowest: .milliseconds(600)
        }
    }

    /// Wait while on track toward the answer — longer patience to let the child
    /// finish saying it.
    var onTrackWait: Duration {
        switch self {
        case .fastest: .milliseconds(600)
        case .fast: .milliseconds(700)
        case .normal: .milliseconds(800)
        case .slow: .milliseconds(900)
        case .slowest: .milliseconds(1000)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceSpeedTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tables/Model/VoiceSpeed.swift TablesTests/VoiceSpeedTests.swift
git commit -m "Add VoiceSpeed with per-notch settle durations"
```

---

### Task 2: `AppSettings.voiceSpeed` persistence

**Files:**
- Modify: `Tables/Services/AppSettings.swift`
- Test: `TablesTests/AppSettingsTests.swift` (add cases)

**Interfaces:**
- Consumes: `VoiceSpeed` (Task 1).
- Produces: `AppSettings.voiceSpeed: VoiceSpeed` (persisted under `"settings.voiceSpeed"`, default `.normal`).

- [ ] **Step 1: Write the failing tests**

Add to `TablesTests/AppSettingsTests.swift` (matching the existing `freshDefaults` idiom):
```swift
    @Test("voice speed defaults to normal and survives a relaunch")
    func voiceSpeedPersists() {
        let defaults = freshDefaults("test.voicespeed")
        #expect(AppSettings(defaults: defaults).voiceSpeed == .normal)

        let first = AppSettings(defaults: defaults)
        first.voiceSpeed = .fastest
        #expect(AppSettings(defaults: defaults).voiceSpeed == .fastest)
    }

    @Test("an out-of-range stored voice speed falls back to normal")
    func voiceSpeedClamped() {
        let defaults = freshDefaults("test.voicespeed.clamp")
        defaults.set(99, forKey: "settings.voiceSpeed")
        #expect(AppSettings(defaults: defaults).voiceSpeed == .normal)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/AppSettingsTests`
Expected: FAIL — `voiceSpeed` doesn't exist.

- [ ] **Step 3: Add the property**

In `Tables/Services/AppSettings.swift`:

3a. Add the key alongside the others:
```swift
    private static let voiceSpeedKey = "settings.voiceSpeed"
```

3b. Add the stored property (after `multipleChoiceOptionCount`):
```swift
    var voiceSpeed: VoiceSpeed {
        didSet { defaults.set(voiceSpeed.rawValue, forKey: Self.voiceSpeedKey) }
    }
```

3c. Initialise it in `init`, after the `multipleChoiceOptionCount` line:
```swift
        let storedSpeed = defaults.object(forKey: Self.voiceSpeedKey) as? Int
        self.voiceSpeed = storedSpeed.flatMap(VoiceSpeed.init(rawValue:)) ?? .normal
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/AppSettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tables/Services/AppSettings.swift TablesTests/AppSettingsTests.swift
git commit -m "Persist a voiceSpeed setting, default normal"
```

---

### Task 3: Drive controller durations from `VoiceSpeed`

**Files:**
- Modify: `Tables/Features/Game/VoiceAnswerController.swift`
- Modify: `TablesTests/VoiceAnswerControllerTests.swift`

**Interfaces:**
- Consumes: `VoiceSpeed` (Task 1); existing `SpokenNumber`, `SettleScheduling`, `GameSession`.
- Produces: `VoiceAnswerController.init(session:recognizer:scheduler:speed:now:)` — new `speed: VoiceSpeed = .normal` param. The static `onTrackWait`/`shortWait` constants are removed.

- [ ] **Step 1: Update the controller tests (RED)**

In `TablesTests/VoiceAnswerControllerTests.swift`:

1a. Change `make()` to accept a speed and pass it. Replace the signature/return line and the `VoiceAnswerController(...)` construction:
```swift
    private func make(speed: VoiceSpeed = .normal)
        -> (VoiceAnswerController, GameSession, FakeAnswerRecognizer, ManualSettleScheduler) {
```
and the controller construction inside `make`:
```swift
        let controller = VoiceAnswerController(
            session: session, recognizer: fake, scheduler: scheduler, speed: speed, now: { self.start }
        )
```

1b. In `extendableWaitsAndPublishes`, change the expected on-track duration from 1200 to the new `.normal` value (800):
```swift
        let expected: Duration = status == .onTrack ? .milliseconds(800) : .milliseconds(400)
```

1c. Add a new test proving the injected speed's durations are used:
```swift
    @Test("the injected speed sets the settle durations")
    func speedDrivesDurations() {
        let (controller, session, fake, scheduler) = make(speed: .fastest)
        controller.syncToPhase()
        let answer = session.fact.answer
        fake.emitPartial(20, isFinal: false)             // extendable, not a ×3/×7 answer
        let status = SpokenNumber.track(heard: 20, answer: answer)
        // Fastest = 200 short / 600 on-track — proves the speed flowed through.
        let expected: Duration = status == .onTrack ? .milliseconds(600) : .milliseconds(200)
        #expect(scheduler.lastDelay == expected)
    }
```

(`matchUsesShortWait` is unchanged — the `.normal` short wait is still 400 ms.)

- [ ] **Step 2: Run the controller suite to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: FAIL — `speed:` init param doesn't exist (and the 800 expectation fails against the current 1200).

- [ ] **Step 3: Add the speed to the controller**

In `Tables/Features/Game/VoiceAnswerController.swift`:

3a. Remove the two static constants:
```swift
    /// Long patience — only when the child is on track toward the answer but
    /// hasn't said it yet, so give them time to finish it.
    private static let onTrackWait: Duration = .milliseconds(1200)
    /// Short insurance — a match (we already have the correct answer, but it
    /// could still grow into a wrong one, e.g. "thirty" → "thirty two") or an
    /// off-track number (already wrong, just capturing the whole of it).
    private static let shortWait: Duration = .milliseconds(400)
```

3b. Add a stored `speed` (near the other stored `let`s, e.g. after `private let now`):
```swift
    private let speed: VoiceSpeed
```

3c. Add the `speed` parameter to `init` (defaulted) and assign it. Change the signature:
```swift
    init(session: GameSession,
         recognizer: any AnswerRecognizing,
         scheduler: (any SettleScheduling)? = nil,
         speed: VoiceSpeed = .normal,
         now: @escaping () -> Date = { Date() }) {
```
and add, alongside the other assignments in the init body:
```swift
        self.speed = speed
```

3d. Change the duration pick (currently `let wait = status == .onTrack ? Self.onTrackWait : Self.shortWait`):
```swift
        let wait = status == .onTrack ? speed.onTrackWait : speed.shortWait
```

- [ ] **Step 4: Run the controller suite (GREEN)**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: PASS.

- [ ] **Step 5: Build the app and run the full unit suite**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED — `VoiceInputView` still constructs the controller without `speed:`, so it defaults to `.normal` (Task 4 wires the real setting).
Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests`
Expected: all unit suites PASS.

- [ ] **Step 6: Commit**

```bash
git add Tables/Features/Game/VoiceAnswerController.swift TablesTests/VoiceAnswerControllerTests.swift
git commit -m "Drive voice settle durations from an injected VoiceSpeed"
```

---

### Task 4: Settings slider + view wiring

**Files:**
- Modify: `Tables/Features/Settings/SettingsView.swift`
- Modify: `Tables/Features/Game/VoiceInputView.swift`

**Interfaces:**
- Consumes: `AppSettings.voiceSpeed` (Task 2), `VoiceSpeed` (Task 1), `SpeechAnswerRecognizer.isSupported`.
- Produces: no new symbols — a slider card in Settings and the controller built with `speed: settings.voiceSpeed`.

Verified by build + the manual device pass (the slider drives real hardware timing; no unit test for the view).

- [ ] **Step 1: Add the slider card to `SettingsView`**

In `Tables/Features/Settings/SettingsView.swift`, add this card in the `VStack` right after the multiple-choice `Card { … }` and before the `Spacer()`:
```swift
                    if SpeechAnswerRecognizer.isSupported {
                        Card {
                            VStack(alignment: .leading, spacing: Metrics.space3) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Voice speed")
                                            .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                                            .foregroundStyle(Color.ink)
                                        Text("How long voice waits for you to finish speaking.")
                                            .font(Typography.ui(12, relativeTo: .caption))
                                            .foregroundStyle(Color.inkSoft)
                                    }
                                    Spacer()
                                    Text(settings.voiceSpeed.label)
                                        .font(Typography.ui(13, weight: .semibold, relativeTo: .footnote))
                                        .foregroundStyle(Color.inkSoft)
                                }

                                Slider(
                                    value: voiceSpeedBinding,
                                    in: 0...Double(VoiceSpeed.allCases.count - 1),
                                    step: 1
                                )
                                .tint(Color.sage)

                                HStack {
                                    Text("Fastest")
                                    Spacer()
                                    Text("Slowest")
                                }
                                .font(Typography.ui(11, relativeTo: .caption2))
                                .foregroundStyle(Color.inkMuted)
                            }
                            .padding(Metrics.space4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
```

Then add this computed binding as a method on `SettingsView` (e.g. just before `toggleRow`):
```swift
    private var voiceSpeedBinding: Binding<Double> {
        Binding(
            get: { Double(settings.voiceSpeed.rawValue) },
            set: { settings.voiceSpeed = VoiceSpeed(rawValue: Int($0.rounded())) ?? .normal }
        )
    }
```

Note: `settings.voiceSpeed = …` mutates the `@Observable AppSettings` reference directly (no `@Bindable` needed for a hand-built `Binding`).

- [ ] **Step 2: Pass the setting into the controller in `VoiceInputView`**

In `Tables/Features/Game/VoiceInputView.swift`:

2a. Add the environment read, after the existing `@Environment` lines (near `@Environment(\.scenePhase)`):
```swift
    @Environment(AppSettings.self) private var settings
```

2b. Change the controller construction (currently `let controller = VoiceAnswerController(session: session, recognizer: recognizer)`):
```swift
        let controller = VoiceAnswerController(session: session, recognizer: recognizer, speed: settings.voiceSpeed)
```

- [ ] **Step 3: Build and run the full unit suite**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED, no new warnings. (`AppSettings` is already in the environment — `GameView` reads it — so `VoiceInputView` can too.)
Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests`
Expected: all unit suites PASS.

- [ ] **Step 4: Commit**

```bash
git add Tables/Features/Settings/SettingsView.swift Tables/Features/Game/VoiceInputView.swift
git commit -m "Add Voice speed slider to Settings and wire it into voice mode"
```

---

### Task 5: Manual device verification

**Files:** none (verification only). No commit unless a fix is needed.

On a real iPhone that supports voice:

- [ ] **Step 1:** Open Settings — confirm the **Voice speed** card appears (only on a voice-capable device), the slider has 5 stops, and the trailing label updates (Fastest…Slowest) as you drag.
- [ ] **Step 2:** Set **Fastest**, play a voice game — confirm answers submit noticeably quicker (short ~200 ms, on-track ~600 ms via the `-voiceDebug` trace). Set **Slowest** and confirm the waits lengthen (~600 / ~1000 ms).
- [ ] **Step 3:** Confirm the choice **persists** across app relaunch.
- [ ] **Step 4:** Confirm a match still submits on the short wait (not the on-track one) at the chosen speed, and terminal answers still submit immediately.

If the numbers need adjusting, they're the `shortWait`/`onTrackWait` values in `VoiceSpeed`.

---

## Notes for the implementer

- `GameSession`, `SpeechAnswerRecognizer`, and `SpokenNumberParser` are not touched.
- Tasks 1–3 each leave the app building (Task 3's controller change keeps a defaulted `speed`, so `VoiceInputView` compiles before Task 4 wires the real value). Task 4 connects the setting.
- The speed is read once per game at controller construction; changing the slider mid-game does not affect the game in progress (out of scope, per the spec).
