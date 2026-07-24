# Voice Answer Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third answer mode where a child speaks the answer and it is recognised on-device and submitted automatically.

**Architecture:** Voice becomes `AnswerMode.voice`. A pure `SpokenNumberParser` turns transcripts into numbers. A `SpeechAnswerRecognizer` (behind the `AnswerRecognizing` protocol) wraps `SFSpeechRecognizer` + `AVAudioEngine` on-device. A `@MainActor @Observable VoiceAnswerController` observes `GameSession.phase`, drives the recognizer's start/stop, and submits recognised numbers through the existing `session.submit(_:now:)` seam. `VoiceInputView` is a thin view over the controller. `GameSession` is unchanged.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, Speech framework (`SFSpeechRecognizer`), AVFoundation (`AVAudioEngine`, `AVAudioSession`), Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Swift concurrency: app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure Sendable value types are marked `nonisolated` (see `AnswerMode`, `GameConfig`). UI/controller types are `@MainActor`.
- On-device recognition only: `requiresOnDeviceRecognition = true`. No audio leaves the device.
- Answer range is **1–144** (tables 1–12 × 1–12). The parser rejects anything outside it.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`/`#require`), `@MainActor struct` suites. Seeded RNG helper is `SeededRandom(seed:)` defined in `TablesTests/DistractorGeneratorTests.swift`. Feedback double is `SilentFeedbackPlayer`.
- Follow `DesignSystem` (Palette/Typography/Metrics/Motion) and respect `accessibilityReduceMotion`.
- Info.plist copy is kid/parent friendly and states on-device processing.

**Test command** (substitute an installed simulator name if `iPhone 16` isn't available — check with `xcrun simctl list devices available`):

```bash
xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/<SuiteName>
```

**Build-only command** (for tasks with no unit tests):

```bash
xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

### Task 1: `SpokenNumberParser` (pure transcript → number)

**Files:**
- Create: `Tables/Model/SpokenNumberParser.swift`
- Test: `TablesTests/SpokenNumberParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum SpokenNumberParser { static func parse(_ transcript: String) -> Int? }`. Returns a number in `1...144` extracted from the transcript, else `nil`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Tables

struct SpokenNumberParserTests {

    @Test("plain digits parse", arguments: [
        ("42", 42), ("7", 7), ("144", 144), ("1", 1)
    ])
    func digits(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("number words parse", arguments: [
        ("forty-two", Optional(42)), ("forty two", 42), ("seven", 7),
        ("one hundred forty-four", 144), ("one hundred and forty four", 144),
        ("twelve", 12), ("forty", 40)
    ])
    func words(input: String, expected: Int?) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("digit-sequence fallback: 'four two' -> 42")
    func digitSequence() {
        #expect(SpokenNumberParser.parse("four two") == 42)
    }

    @Test("kid homophones", arguments: [
        ("to", 2), ("too", 2), ("for", 4), ("ate", 8), ("free", 3), ("tree", 3)
    ])
    func homophones(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("extracts a number from a phrase", arguments: [
        ("um forty two", 42), ("the answer is 42", 42), ("i think it's nine", 9)
    ])
    func phrases(input: String, expected: Int) {
        #expect(SpokenNumberParser.parse(input) == expected)
    }

    @Test("rejects out-of-range and noise", arguments: [
        "banana", "two hundred", "1000", "", "hello there", "145"
    ])
    func rejects(input: String) {
        #expect(SpokenNumberParser.parse(input) == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SpokenNumberParserTests`
Expected: FAIL — `SpokenNumberParser` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Turns a speech transcript into an answer number, or `nil`.
///
/// Scoped to the game's answer range (1–144), so background chatter and
/// out-of-range utterances resolve to nothing rather than a wrong guess.
///
/// `nonisolated`: a pure Sendable helper should not be main-actor-isolated
/// just because the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION`.
nonisolated enum SpokenNumberParser {

    private static let maxAnswer = 144

    /// Single-token words → value. Includes number words 0–20, the tens, and
    /// the homophones a child reliably triggers ("to"→2, "ate"→8, "tree"→3).
    private static let words: [String: Int] = [
        "zero": 0, "oh": 0,
        "one": 1, "won": 1,
        "two": 2, "to": 2, "too": 2,
        "three": 3, "free": 3, "tree": 3,
        "four": 4, "for": 4, "fore": 4,
        "five": 5, "six": 6, "sicks": 6,
        "seven": 7, "eight": 8, "ate": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "hundred": 100
    ]

    static func parse(_ transcript: String) -> Int? {
        let tokens = tokenize(transcript)
        guard !tokens.isEmpty else { return nil }

        // 1. A bare integer in range anywhere in the phrase wins
        //    ("the answer is 42" → 42). Out-of-range ints are skipped.
        for token in tokens {
            if let value = Int(token), inRange(value) { return value }
        }

        // 2. Gather the number-words in order, dropping filler words
        //    ("um forty two" → [40, 2]; "i think it's nine" → [9]).
        let values = tokens.compactMap { words[$0] }
        guard !values.isEmpty else { return nil }

        // 2a. Two or more spoken single digits are a digit sequence, not a sum:
        //     "four two" → "42", "eight eight" → "88".
        if values.count >= 2, values.allSatisfy({ (0...9).contains($0) }) {
            guard let value = Int(values.map(String.init).joined()) else { return nil }
            return inRange(value) ? value : nil
        }

        // 2b. Standard number-word accumulation: "forty two" → 42,
        //     "one hundred forty four" → 144, "two hundred" → 200 (rejected).
        let value = accumulate(values)
        return inRange(value) ? value : nil
    }

    private static func inRange(_ value: Int) -> Bool { value >= 1 && value <= maxAnswer }

    private static func tokenize(_ transcript: String) -> [String] {
        transcript
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "and" }
    }

    /// Classic accumulate: units/tens add to a running part, "hundred" scales it.
    private static func accumulate(_ values: [Int]) -> Int {
        var total = 0
        var current = 0
        for value in values {
            if value == 100 {
                current = max(current, 1) * 100
            } else {
                current += value
            }
            if current >= 100 {
                total += current
                current = 0
            }
        }
        return total + current
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SpokenNumberParserTests`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add Tables/Model/SpokenNumberParser.swift TablesTests/SpokenNumberParserTests.swift
git commit -m "Add SpokenNumberParser for voice answers"
```

---

### Task 2: `AnswerMode.voice` case

**Files:**
- Modify: `Tables/Model/AnswerMode.swift`
- Test: `TablesTests/AnswerModeTests.swift` (create)

**Interfaces:**
- Consumes: existing `AnswerMode`.
- Produces: `AnswerMode.voice` with `title == "Voice"`, `subtitle == "Say the answer"`. Now `AnswerMode.allCases == [.multipleChoice, .numberPad, .voice]`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import Tables

struct AnswerModeTests {
    @Test("voice case exists with copy")
    func voice() {
        #expect(AnswerMode.voice.rawValue == "voice")
        #expect(AnswerMode.voice.title == "Voice")
        #expect(AnswerMode.voice.subtitle == "Say the answer")
        #expect(AnswerMode.allCases.contains(.voice))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/AnswerModeTests`
Expected: FAIL — `voice` is not a member of `AnswerMode`.

- [ ] **Step 3: Write minimal implementation**

In `Tables/Model/AnswerMode.swift`, add the case and its copy:

```swift
nonisolated enum AnswerMode: String, CaseIterable, Codable, Sendable {
    case multipleChoice
    case numberPad
    case voice

    var title: String {
        switch self {
        case .multipleChoice: "Multiple choice"
        case .numberPad: "Number pad"
        case .voice: "Voice"
        }
    }

    var subtitle: String {
        switch self {
        case .multipleChoice: "Pick from the tiles"
        case .numberPad: "Type the answer"
        case .voice: "Say the answer"
        }
    }
}
```

- [ ] **Step 4: Add a temporary `.voice` arm to `GameView` so the app still compiles**

Adding `.voice` makes `GameView`'s `switch config.answerMode` non-exhaustive. Because every `TablesTests` suite does `@testable import Tables`, the app target must compile for *any* test to run — so this can't be deferred. Add a temporary arm routing to the number pad (Task 7 replaces it with `VoiceInputView`).

In `Tables/Features/Game/GameView.swift`, in the `switch config.answerMode` block (~line 124):

```swift
                switch config.answerMode {
                case .multipleChoice:
                    MultipleChoiceView(session: session)
                case .numberPad:
                    NumberPadView(session: session)
                case .voice:
                    // TODO(Task 7): replace with VoiceInputView(session: session)
                    NumberPadView(session: session)
                }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/AnswerModeTests`
Expected: PASS (app now compiles; the AnswerMode suite runs green).

- [ ] **Step 6: Commit**

```bash
git add Tables/Model/AnswerMode.swift TablesTests/AnswerModeTests.swift Tables/Features/Game/GameView.swift
git commit -m "Add voice case to AnswerMode"
```

---

### Task 3: `AnswerRecognizing` protocol + `FakeAnswerRecognizer`

**Files:**
- Create: `Tables/Services/AnswerRecognizing.swift`
- Create: `TablesTests/FakeAnswerRecognizer.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@MainActor protocol AnswerRecognizing: AnyObject { var onNumber: ((Int) -> Void)? { get set }; func requestAuthorization(_ completion: @escaping (Bool) -> Void); func start(); func stop() }`
  - `@MainActor final class FakeAnswerRecognizer: AnswerRecognizing` with test hooks: `var isListening: Bool`, `var startCount: Int`, `var stopCount: Int`, `var authorized: Bool` (default true), and `func emit(_ number: Int)` which calls `onNumber` (only while listening).

- [ ] **Step 1: Write the protocol (app target)**

`Tables/Services/AnswerRecognizing.swift`:

```swift
import Foundation

/// A source of recognised answer numbers. Abstracted so the game can run
/// against a fake (previews, tests) with no microphone.
@MainActor
protocol AnswerRecognizing: AnyObject {
    /// Fires once per recognised number while listening.
    var onNumber: ((Int) -> Void)? { get set }

    /// Request microphone + speech authorization. `granted` is true only when
    /// both are available. Safe to call repeatedly.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)

    /// Begin listening. Idempotent while already listening.
    func start()

    /// Stop listening and release the audio buffer.
    func stop()
}
```

- [ ] **Step 2: Write the fake (test target)**

`TablesTests/FakeAnswerRecognizer.swift`:

```swift
import Foundation
@testable import Tables

@MainActor
final class FakeAnswerRecognizer: AnswerRecognizing {
    var onNumber: ((Int) -> Void)?

    var authorized = true
    private(set) var isListening = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        completion(authorized)
    }

    func start() {
        startCount += 1
        isListening = true
    }

    func stop() {
        if isListening { stopCount += 1 }
        isListening = false
    }

    /// Simulate the recogniser hearing a number. No-op unless listening,
    /// mirroring the real recogniser which only emits between start/stop.
    func emit(_ number: Int) {
        guard isListening else { return }
        onNumber?(number)
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED (this task adds no non-exhaustive switch; Task 2's `GameView` gap is still open, so if Task 2 is already applied this build fails until Task 7 — in that case skip this build check and rely on Task 4's suite run).

- [ ] **Step 4: Commit**

```bash
git add Tables/Services/AnswerRecognizing.swift TablesTests/FakeAnswerRecognizer.swift
git commit -m "Add AnswerRecognizing protocol and test fake"
```

---

### Task 4: `VoiceAnswerController` (phase-driven orchestration)

**Files:**
- Create: `Tables/Features/Game/VoiceAnswerController.swift`
- Test: `TablesTests/VoiceAnswerControllerTests.swift`

**Interfaces:**
- Consumes: `GameSession` (has `var phase: Phase`, `func submit(_:now:)`), `AnswerRecognizing`, `SpokenNumberParser` (indirectly via the recognizer — controller receives already-parsed `Int`s).
- Produces:
  - `@MainActor @Observable final class VoiceAnswerController`
  - `init(session: GameSession, recognizer: any AnswerRecognizing, now: @escaping () -> Date = { Date() })`
  - `enum Display: Equatable { case idle, listening, heard(Int) }`, `private(set) var display: Display`
  - `func syncToPhase()` — call on appear and on every `session.phase` change.
  - `func requestAuthorization(_ completion: @escaping (Bool) -> Void)` — forwards to the recognizer.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct VoiceAnswerControllerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func make() -> (VoiceAnswerController, GameSession, FakeAnswerRecognizer) {
        let config = GameConfig(mode: .countdown, tables: [3, 7], answerMode: .voice, length: .seconds(60))
        let session = GameSession(
            config: config,
            store: InMemoryProgressStore(),
            optionCount: 6,
            feedback: SilentFeedbackPlayer(),
            rng: SeededRandom(seed: 17)
        )
        session.start(now: start)
        let fake = FakeAnswerRecognizer()
        let controller = VoiceAnswerController(session: session, recognizer: fake, now: { self.start })
        return (controller, session, fake)
    }

    @Test("syncToPhase starts listening while asking")
    func startsOnAsking() {
        let (controller, session, fake) = make()
        #expect(session.phase == .asking)
        controller.syncToPhase()
        #expect(fake.isListening)
        #expect(controller.display == .listening)
    }

    @Test("a heard number submits through the session")
    func submits() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        let answer = session.fact.answer
        fake.emit(answer)
        // Correct answer in countdown scores and enters feedback.
        #expect(session.score == 1)
        #expect(fake.isListening == false)          // stopped after a hit
        if case .heard(let n) = controller.display { #expect(n == answer) } else { Issue.record("expected .heard") }
    }

    @Test("stops listening when the question is not asking")
    func stopsOffAsking() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        #expect(fake.isListening)
        // Submit a wrong answer to leave .asking (countdown feedback hold).
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)
        controller.syncToPhase()
        #expect(fake.isListening == false)
        #expect(controller.display == .idle)
    }

    @Test("a number heard when not asking is ignored")
    func ignoresWhenNotAsking() {
        let (controller, session, fake) = make()
        controller.syncToPhase()
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)   // -> feedback
        controller.syncToPhase()            // -> stop
        fake.emit(99)                       // fake ignores because not listening
        #expect(session.answered == 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: FAIL — `VoiceAnswerController` is not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import Observation

/// Bridges a `GameSession` to an `AnswerRecognizing` source.
///
/// It listens only while the question is `.asking`, submits the first number it
/// hears through the same `submit(_:now:)` seam the number pad uses, and stops
/// during feedback holds. All audio lives in the recogniser; this controller is
/// pure enough to test with a fake and a seeded session.
@MainActor
@Observable
final class VoiceAnswerController {

    enum Display: Equatable {
        case idle
        case listening
        case heard(Int)
    }

    private(set) var display: Display = .idle

    private let session: GameSession
    private let recognizer: any AnswerRecognizing
    private let now: () -> Date

    init(session: GameSession, recognizer: any AnswerRecognizing, now: @escaping () -> Date = { Date() }) {
        self.session = session
        self.recognizer = recognizer
        self.now = now
        self.recognizer.onNumber = { [weak self] number in
            self?.handle(number)
        }
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        recognizer.requestAuthorization(completion)
    }

    /// Call on appear and whenever `session.phase` changes.
    func syncToPhase() {
        if session.phase == .asking {
            if display != .listening {
                display = .listening
                recognizer.start()
            }
        } else {
            stop()
        }
    }

    private func handle(_ number: Int) {
        guard session.phase == .asking else { return }
        display = .heard(number)
        recognizer.stop()
        session.submit(number, now: now())
    }

    private func stop() {
        guard display != .idle else { return }
        display = .idle
        recognizer.stop()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tables/Features/Game/VoiceAnswerController.swift TablesTests/VoiceAnswerControllerTests.swift
git commit -m "Add VoiceAnswerController driving submit from recognised numbers"
```

---

### Task 5: `SpeechAnswerRecognizer` (real on-device recogniser) + Info.plist

**Files:**
- Create: `Tables/Services/SpeechAnswerRecognizer.swift`
- Modify: `Tables/Info.plist`

**Interfaces:**
- Consumes: `AnswerRecognizing`, `SpokenNumberParser`.
- Produces:
  - `@MainActor final class SpeechAnswerRecognizer: AnswerRecognizing`
  - `static var isSupported: Bool` — true when a recogniser exists for the locale and `supportsOnDeviceRecognition` is true.

This task has no unit tests — `SFSpeechRecognizer`/`AVAudioEngine` need real hardware. Verify it **builds**, and record device testing in Task 8's checklist.

- [ ] **Step 1: Add Info.plist usage strings**

Add these two keys to `Tables/Info.plist` (inside the top-level `<dict>`):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Tables listens so you can say your answers out loud.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Tables turns what you say into your answer. Speech is processed on your device.</string>
```

- [ ] **Step 2: Write the recogniser**

`Tables/Services/SpeechAnswerRecognizer.swift`:

```swift
import Foundation
import Speech
import AVFoundation

/// On-device speech recognition, scoped to hearing a single answer number.
///
/// Forces `requiresOnDeviceRecognition` so nothing leaves the phone. Each
/// `start()` opens a fresh recognition request; the first partial transcript
/// that `SpokenNumberParser` resolves to a valid number fires `onNumber` once
/// and then the recogniser stops itself.
@MainActor
final class SpeechAnswerRecognizer: AnswerRecognizing {

    var onNumber: ((Int) -> Void)?

    /// Whether this device can offer voice mode at all (shown-in-setup gate).
    static var isSupported: Bool {
        guard let recognizer = SFSpeechRecognizer() else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false
    private var didFire = false

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                Task { @MainActor in completion(false) }
                return
            }
            AVAudioApplication.requestRecordPermission { micGranted in
                Task { @MainActor in completion(micGranted) }
            }
        }
    }

    func start() {
        guard !isRunning, let recognizer, recognizer.isAvailable else { return }
        isRunning = true
        didFire = false

        // Re-assert the record category on every start so it wins over
        // FeedbackPlayer's `.ambient`. `.duckOthers` lets our tones through.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result, let number = SpokenNumberParser.parse(result.bestTranscription.formattedString) {
                    self.fire(number)
                } else if error != nil {
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func fire(_ number: Int) {
        guard isRunning, !didFire else { return }
        didFire = true
        onNumber?(number)
        stop()
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED. (`GameView`'s switch is still non-exhaustive until Task 7 — if that task isn't done yet, this build fails on `GameView.swift` only. That's expected; proceed to Task 6/7 and rely on the Task 7 build.)

- [ ] **Step 4: Commit**

```bash
git add Tables/Services/SpeechAnswerRecognizer.swift Tables/Info.plist
git commit -m "Add on-device SpeechAnswerRecognizer and mic/speech usage strings"
```

---

### Task 6: Setup gating & persistence

**Files:**
- Modify: `Tables/Features/Setup/SetupModel.swift`
- Modify: `Tables/Features/Setup/SetupView.swift`
- Test: `TablesTests/SetupModelTests.swift` (add cases)

**Interfaces:**
- Consumes: `AnswerMode`, `SpeechAnswerRecognizer.isSupported`.
- Produces on `SetupModel`:
  - `init(mode:defaults:isVoiceSupported:)` — new parameter `isVoiceSupported: Bool = SpeechAnswerRecognizer.isSupported`.
  - `let isVoiceSupported: Bool`
  - `var availableAnswerModes: [AnswerMode]` — `AnswerMode.allCases` minus `.voice` when unsupported.
  - `loadAnswerMode` falls back to `.multipleChoice` when the stored mode is `.voice` but voice is unsupported.

- [ ] **Step 1: Write the failing tests**

Add to `TablesTests/SetupModelTests.swift` (match the file's existing suite/struct and its UserDefaults idiom — create an ephemeral suite the way the existing tests do):

```swift
    @Test("voice is offered only when supported")
    func voiceGating() {
        let defaults = UserDefaults(suiteName: "voice.gating.\(UUID().uuidString)")!
        let supported = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: true)
        #expect(supported.availableAnswerModes.contains(.voice))
        let unsupported = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: false)
        #expect(unsupported.availableAnswerModes.contains(.voice) == false)
    }

    @Test("a stored voice mode falls back when unsupported")
    func voiceFallback() {
        let defaults = UserDefaults(suiteName: "voice.fallback.\(UUID().uuidString)")!
        defaults.set(AnswerMode.voice.rawValue, forKey: "setup.answerMode")
        let model = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: false)
        #expect(model.answerMode == .multipleChoice)
    }

    @Test("a stored voice mode is kept when supported")
    func voiceKept() {
        let defaults = UserDefaults(suiteName: "voice.kept.\(UUID().uuidString)")!
        defaults.set(AnswerMode.voice.rawValue, forKey: "setup.answerMode")
        let model = SetupModel(mode: .countdown, defaults: defaults, isVoiceSupported: true)
        #expect(model.answerMode == .voice)
    }
```

Note: these tests write to `defaults` directly, so they rely on `persists == true`. `persists` is false only under the `-uiTesting` launch argument, which unit tests do not pass — so persistence is active here, matching the existing SetupModel tests.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SetupModelTests`
Expected: FAIL — `init(mode:defaults:isVoiceSupported:)` and `availableAnswerModes` don't exist.

- [ ] **Step 3: Implement gating in `SetupModel`**

Add the stored property and parameter, and gate load/available. Change the `init` signature and body:

```swift
    let isVoiceSupported: Bool

    init(mode: GameMode, defaults: UserDefaults = .standard, isVoiceSupported: Bool = SpeechAnswerRecognizer.isSupported) {
        self.mode = mode
        self.defaults = defaults
        self.isVoiceSupported = isVoiceSupported
        self.persists = !ProcessInfo.processInfo.arguments.contains("-uiTesting")

        if persists {
            self.tables = Self.loadTables(from: defaults)
            self.answerMode = Self.loadAnswerMode(from: defaults, isVoiceSupported: isVoiceSupported)
            self.length = Self.loadLength(from: defaults, mode: mode) ?? Self.defaultLength(mode)
        } else {
            self.tables = []
            self.answerMode = .multipleChoice
            self.length = Self.defaultLength(mode)
        }
        self.openSection = .tables
    }

    /// Answer modes offered on this device. Voice needs on-device recognition.
    var availableAnswerModes: [AnswerMode] {
        AnswerMode.allCases.filter { $0 != .voice || isVoiceSupported }
    }
```

Update `loadAnswerMode` to take the flag and fall back:

```swift
    private static func loadAnswerMode(from defaults: UserDefaults, isVoiceSupported: Bool) -> AnswerMode {
        guard let raw = defaults.string(forKey: answerModeKey),
              let mode = AnswerMode(rawValue: raw) else { return .multipleChoice }
        if mode == .voice && !isVoiceSupported { return .multipleChoice }
        return mode
    }
```

- [ ] **Step 4: Update `SetupView` to use `availableAnswerModes` and drop the placeholder**

In `Tables/Features/Setup/SetupView.swift`, replace the `answerModeSection` body so it iterates the model's available modes and removes the "Soon" placeholder:

```swift
    private var answerModeSection: some View {
        section(.answerMode, label: "Answer mode", summary: model.answerMode.title) {
            VStack(spacing: Metrics.space2) {
                ForEach(model.availableAnswerModes, id: \.self) { mode in
                    answerRow(mode)
                }
            }
        }
    }
```

Delete the now-unused `voiceRow` computed property (the whole `private var voiceRow: some View { ... }` block, lines ~167–191). Leave `StatusChip`/`Chip.swift` in place — it may be used elsewhere; only the `voiceRow` reference to it is removed.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SetupModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Tables/Features/Setup/SetupModel.swift Tables/Features/Setup/SetupView.swift TablesTests/SetupModelTests.swift
git commit -m "Gate voice answer mode on device support in setup"
```

---

### Task 7: `VoiceInputView` + `GameView` branch + permission fallback

**Files:**
- Create: `Tables/Features/Game/VoiceInputView.swift`
- Modify: `Tables/Features/Game/GameView.swift` (the `switch config.answerMode` block, ~line 124, and the `problem` size line, ~line 144)

**Interfaces:**
- Consumes: `GameSession`, `VoiceAnswerController`, `SpeechAnswerRecognizer`, `AppSettings` (already in `GameView`), `accessibilityReduceMotion`.
- Produces: `struct VoiceInputView: View { init(session: GameSession) }`.

This view drives real hardware; it is verified by **building** and by the manual device checklist in Task 8, not unit tests.

- [ ] **Step 1: Point the `.voice` branch at the real view in `GameView`**

Task 2 added a temporary `.voice` arm routing to `NumberPadView` (with a `TODO(Task 7)` comment). Replace that arm's body with the real view:

```swift
                switch config.answerMode {
                case .multipleChoice:
                    MultipleChoiceView(session: session)
                case .numberPad:
                    NumberPadView(session: session)
                case .voice:
                    VoiceInputView(session: session)
                }
```

And in the `problem` size line (~144), treat voice like the number pad (52):

```swift
        let size: CGFloat = config.answerMode == .multipleChoice ? 56 : 52
```

(No change needed — `.voice` already falls into the non-`.multipleChoice` branch. Verify this line reads as above.)

- [ ] **Step 2: Write `VoiceInputView`**

`Tables/Features/Game/VoiceInputView.swift`:

```swift
import SwiftUI

/// The `.voice` answer mode. Always listening while a question is shown; a
/// recognised number submits through the shared `session.submit` seam. The
/// mic pulses while listening and flashes the heard number, echoing the
/// number pad's sage/blush feedback so voice feels of a piece with the app.
struct VoiceInputView: View {
    let session: GameSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var controller: VoiceAnswerController?
    @State private var recognizer = SpeechAnswerRecognizer()
    @State private var permissionDenied = false

    private var isWrong: Bool {
        switch session.phase {
        case .feedback(let ok, _): !ok
        case .reviewing: true
        default: false
        }
    }

    private var isCorrect: Bool {
        if case .feedback(true, _) = session.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: Metrics.space3 + 2) {
            if permissionDenied {
                deniedNotice
            } else {
                heardDisplay
                micIndicator
            }
        }
        .onAppear(perform: startIfNeeded)
        .onChange(of: session.phase) { _, _ in
            controller?.syncToPhase()
        }
    }

    private func startIfNeeded() {
        guard controller == nil else {
            controller?.syncToPhase()
            return
        }
        let controller = VoiceAnswerController(session: session, recognizer: recognizer)
        self.controller = controller
        controller.requestAuthorization { granted in
            if granted {
                permissionDenied = false
                controller.syncToPhase()
            } else {
                permissionDenied = true
            }
        }
    }

    // MARK: Listening UI

    private var displayText: String {
        guard let controller else { return " " }
        if case .heard(let n) = controller.display { return String(n) }
        return " "
    }

    private var displayBorder: Color {
        if isCorrect { return .sage }
        if isWrong { return .blush }
        return .line
    }

    private var heardDisplay: some View {
        Text(displayText)
            .font(Typography.display(34, relativeTo: .largeTitle))
            .foregroundStyle(isWrong ? Color.blushText : Color.ink)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isWrong ? Color.blushTint : Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.radiusTile, style: .continuous)
                    .strokeBorder(displayBorder, lineWidth: Metrics.strokeTile)
            }
            .accessibilityLabel(displayText == " " ? "Listening" : "Heard \(displayText)")
    }

    private var isListening: Bool {
        if case .listening = controller?.display { return true }
        return false
    }

    private var micIndicator: some View {
        VStack(spacing: Metrics.space2) {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(isListening ? Color.ink : Color.inkSoft)
                .scaleEffect(isListening && !reduceMotion ? 1.08 : 1.0)
                .animation(
                    Motion.animation(
                        .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                        reduceMotion: reduceMotion
                    ),
                    value: isListening
                )
            Text("Say your answer")
                .font(Typography.ui(13, relativeTo: .footnote))
                .foregroundStyle(Color.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space4)
    }

    // MARK: Permission denied

    private var deniedNotice: some View {
        VStack(spacing: Metrics.space3) {
            Text("Voice needs microphone access")
                .font(Typography.ui(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: Metrics.space2) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Use keypad") {
                    permissionDenied = false
                    fellBackToKeypad = true
                }
            }
            .font(Typography.ui(14, weight: .semibold, relativeTo: .subheadline))
            if fellBackToKeypad {
                NumberPadView(session: session)
            }
        }
        .padding(.vertical, Metrics.space4)
    }

    @State private var fellBackToKeypad = false
}
```

- [ ] **Step 3: Verify the whole app builds**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED (switch is now exhaustive; view compiles).

- [ ] **Step 4: Run the full test suite**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: all suites PASS.

- [ ] **Step 5: Commit**

```bash
git add Tables/Features/Game/VoiceInputView.swift Tables/Features/Game/GameView.swift
git commit -m "Add VoiceInputView and wire voice answer mode into the game"
```

---

### Task 8: Manual device verification

**Files:** none (verification only). No commit unless a fix is needed.

On-device speech, mic capture, and permission dialogs can't be unit-tested. On a real iPhone that supports on-device recognition:

- [ ] **Step 1:** In Setup, confirm the **Voice** row appears (it should, on a supported device) and can be selected.
- [ ] **Step 2:** Start a Countdown game in voice mode. On first run, confirm both the **speech recognition** and **microphone** permission dialogs appear, with the Info.plist copy.
- [ ] **Step 3:** Grant permission. Confirm the mic pulses, say answers aloud, and confirm correct numbers submit and advance; wrong ones re-ask (countdown) / reveal (revision).
- [ ] **Step 4:** Confirm the correct/incorrect feedback **tones still play** while the mic is active (audio-session coexistence with `FeedbackPlayer`).
- [ ] **Step 5:** Delete + reinstall, start a voice game, and **deny** permission. Confirm the "Voice needs microphone access" notice with **Open Settings** and **Use keypad**, and that **Use keypad** lets the game continue.
- [ ] **Step 6:** Background the app mid-question and return; confirm listening resumes cleanly and there's no stuck audio session.

---

## Notes for the implementer

- `GameSession` is intentionally untouched. If you feel the need to add a voice-specific method to it, stop — the seam is `submit(_:now:)`, already used by the number pad.
- Because every `TablesTests` suite does `@testable import Tables`, the app target must compile for *any* test to run. Task 2 therefore adds a temporary `.voice` switch arm in `GameView` (routing to `NumberPadView`) so the app stays buildable from Task 2 onward; Task 7 swaps that arm's body to `VoiceInputView`. Every task from 2 on can run its named test suite against a compiling app target.
