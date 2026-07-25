# Answer-Aware Voice Settle + Progress Event — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the voice-mode settle window depend on whether what's heard could still become the correct answer (on-track waits longer, off-track waits the current short time), and publish an observable `progress` event carrying the heard number + on-track status.

**Architecture:** The settle timer moves out of `SpeechAnswerRecognizer` (which becomes a pure partial stream) and up into `VoiceAnswerController` (which knows `session.fact.answer`). A pure `SpokenNumber` helper decides on-track status via canonical-word prefixes. The timer sits behind a `SettleScheduling` seam so tests run without real waits. `GameSession` is unchanged.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, `Duration`/`Task.sleep`, Speech/AVFoundation (unchanged parts), Swift Testing.

## Global Constraints

- App target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure Sendable value types are `nonisolated` (as `AnswerMode`, `GameConfig`, `SpokenNumberParser`). UI/controller/recognizer types are `@MainActor`.
- Answer range is 1…144.
- Durations: on-track (`.matches` and `.onTrack`) **1200 ms**, off-track **400 ms**. A terminal (non-extendable) number submits immediately; `isFinal` submits immediately.
- `VoiceProgress` payload is exactly `{ heard: Int, status: .matches | .onTrack | .offTrack }` — no transcript.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), `@MainActor struct` suites. Seeded RNG is `SeededRandom(seed:)` (in `TablesTests/DistractorGeneratorTests.swift`); feedback double `SilentFeedbackPlayer`.
- `GameSession` must not be modified.

**Test command** (substitute an installed simulator if `iPhone 17` isn't present — `xcrun simctl list devices available`):
```bash
xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/<SuiteName>
```
**Build-only:**
```bash
xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'
```
Run xcodebuild in the FOREGROUND (single blocking call); do not poll with a background Monitor.

---

### Task 1: `VoiceProgress` + `SpokenNumber` (pure on-track logic)

**Files:**
- Create: `Tables/Model/VoiceProgress.swift`
- Create: `Tables/Model/SpokenNumber.swift`
- Test: `TablesTests/SpokenNumberTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct VoiceProgress: Equatable, Sendable { enum Status: Equatable, Sendable { case matches, onTrack, offTrack }; let heard: Int; let status: Status }`
  - `enum SpokenNumber { static func words(_ n: Int) -> [String]; static func isExtendable(_ n: Int) -> Bool; static func track(heard: Int, answer: Int) -> VoiceProgress.Status }`

- [ ] **Step 1: Write the failing test**

`TablesTests/SpokenNumberTests.swift`:
```swift
import Testing
@testable import Tables

struct SpokenNumberTests {

    @Test("canonical words", arguments: [
        (3, ["three"]),
        (30, ["thirty"]),
        (36, ["thirty", "six"]),
        (7, ["seven"]),
        (20, ["twenty"]),
        (99, ["ninety", "nine"]),
        (100, ["one", "hundred"]),
        (105, ["one", "hundred", "five"]),
        (120, ["one", "hundred", "twenty"]),
        (144, ["one", "hundred", "forty", "four"]),
    ])
    func words(n: Int, expected: [String]) {
        #expect(SpokenNumber.words(n) == expected)
    }

    @Test("isExtendable", arguments: [
        (1, true), (20, true), (90, true), (100, true), (140, true),
        (7, false), (11, false), (36, false), (42, false), (99, false),
    ])
    func extendable(n: Int, expected: Bool) {
        #expect(SpokenNumber.isExtendable(n) == expected)
    }

    @Test("track vs answer 36", arguments: [
        (36, VoiceProgress.Status.matches),
        (30, .onTrack),
        (3, .offTrack),
        (40, .offTrack),
        (42, .offTrack),
        (20, .offTrack),
    ])
    func track36(heard: Int, expected: VoiceProgress.Status) {
        #expect(SpokenNumber.track(heard: heard, answer: 36) == expected)
    }

    @Test("track vs answer 144", arguments: [
        (144, VoiceProgress.Status.matches),
        (1, .onTrack),
        (100, .onTrack),
        (140, .onTrack),
        (120, .offTrack),
        (36, .offTrack),
    ])
    func track144(heard: Int, expected: VoiceProgress.Status) {
        #expect(SpokenNumber.track(heard: heard, answer: 144) == expected)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SpokenNumberTests`
Expected: FAIL — `VoiceProgress` / `SpokenNumber` undefined.

- [ ] **Step 3: Write the implementation**

`Tables/Model/VoiceProgress.swift`:
```swift
import Foundation

/// A snapshot of what the voice recogniser has heard so far, published for the
/// UI while a still-growing number is settling.
///
/// `nonisolated`: a pure Sendable value type shouldn't be main-actor-isolated
/// just because the app target defaults to `SWIFT_DEFAULT_ACTOR_ISOLATION`.
nonisolated struct VoiceProgress: Equatable, Sendable {
    /// Whether the heard number can still become the expected answer.
    enum Status: Equatable, Sendable {
        case matches    // heard == the expected answer
        case onTrack    // heard != answer but could still become it
        case offTrack   // cannot become the answer
    }

    let heard: Int
    let status: Status
}
```

`Tables/Model/SpokenNumber.swift`:
```swift
import Foundation

/// Number-word reasoning over answer numbers (1…144) — the inverse of
/// `SpokenNumberParser`. Used to decide whether a partially-heard number could
/// still grow into the correct answer.
///
/// `nonisolated`: pure Sendable helper (see `SpokenNumberParser`).
nonisolated enum SpokenNumber {

    private static let ones = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    private static let tens = [
        20: "twenty", 30: "thirty", 40: "forty", 50: "fifty",
        60: "sixty", 70: "seventy", 80: "eighty", 90: "ninety",
    ]

    /// Canonical spoken words for `n` (1…144). 36 -> ["thirty","six"].
    static func words(_ n: Int) -> [String] {
        if n < 20 { return [ones[n]] }
        if n < 100 {
            let t = (n / 10) * 10
            let u = n % 10
            return u == 0 ? [tens[t]!] : [tens[t]!, ones[u]]
        }
        let rest = n - 100
        return rest == 0 ? ["one", "hundred"] : ["one", "hundred"] + words(rest)
    }

    /// Whether `n` could still grow if the child keeps speaking: the tens
    /// ("twenty" -> "twenty one"), "one" (-> "one hundred …"), and any hundred
    /// (over-inclusive on purpose — waiting a beat on 100–144 is cheap, clipping
    /// "one hundred forty four" is not).
    static func isExtendable(_ n: Int) -> Bool {
        n == 1 || (n >= 20 && n <= 90 && n % 10 == 0) || n >= 100
    }

    /// Status of a heard number against the expected answer, by comparing
    /// canonical-word prefixes (so "three"/3 is off-track for 36 but "thirty"/30
    /// is on-track).
    static func track(heard: Int, answer: Int) -> VoiceProgress.Status {
        if heard == answer { return .matches }
        let h = words(heard)
        let a = words(answer)
        return h.count < a.count && Array(a.prefix(h.count)) == h ? .onTrack : .offTrack
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/SpokenNumberTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tables/Model/VoiceProgress.swift Tables/Model/SpokenNumber.swift TablesTests/SpokenNumberTests.swift
git commit -m "Add SpokenNumber on-track logic and VoiceProgress type"
```

---

### Task 2: `SettleScheduling` seam + schedulers

**Files:**
- Create: `Tables/Features/Game/SettleScheduling.swift`
- Create: `TablesTests/ManualSettleScheduler.swift`
- Test: `TablesTests/ManualSettleSchedulerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `@MainActor protocol SettleScheduling: AnyObject { func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void); func cancel() }`
  - `@MainActor final class TaskSettleScheduler: SettleScheduling` (real, `Task.sleep`-based)
  - `@MainActor final class ManualSettleScheduler: SettleScheduling` (test double: `var lastDelay: Duration?`, `func fire()`)

- [ ] **Step 1: Write the app-target seam**

`Tables/Features/Game/SettleScheduling.swift`:
```swift
import Foundation

/// Schedules the single deferred "the number has settled, submit it" action.
/// Abstracted so the controller can be tested without real waits.
@MainActor
protocol SettleScheduling: AnyObject {
    /// Run `action` after `delay`, cancelling any previously-scheduled action.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
    /// Cancel a pending action, if any.
    func cancel()
}

/// Real scheduler: one cancellable `Task.sleep`.
@MainActor
final class TaskSettleScheduler: SettleScheduling {
    private var task: Task<Void, Never>?

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
```

- [ ] **Step 2: Write the test double**

`TablesTests/ManualSettleScheduler.swift`:
```swift
import Foundation
@testable import Tables

/// Test scheduler: records the requested delay and lets the test fire the
/// pending action manually, so settle behaviour is verified without waiting.
@MainActor
final class ManualSettleScheduler: SettleScheduling {
    private(set) var lastDelay: Duration?
    private var action: (@MainActor () -> Void)?

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        lastDelay = delay
        self.action = action
    }

    /// Cancels the pending action. `lastDelay` is left as-is so a test can still
    /// inspect the most recently requested delay after a submit cancels it.
    func cancel() {
        action = nil
    }

    /// Invoke the currently-scheduled action, as the real timer would on timeout.
    func fire() {
        let action = self.action
        self.action = nil
        action?()
    }

    var hasPendingAction: Bool { action != nil }
}
```

- [ ] **Step 3: Write a test for the test double**

`TablesTests/ManualSettleSchedulerTests.swift`:
```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct ManualSettleSchedulerTests {
    @Test("records delay and fires the latest action once")
    func recordsAndFires() {
        let scheduler = ManualSettleScheduler()
        var fired = 0
        scheduler.schedule(after: .milliseconds(400)) { fired += 1 }
        #expect(scheduler.lastDelay == .milliseconds(400))
        // A second schedule replaces the first.
        scheduler.schedule(after: .milliseconds(1200)) { fired += 10 }
        #expect(scheduler.lastDelay == .milliseconds(1200))
        scheduler.fire()
        #expect(fired == 10)          // only the latest action ran
        scheduler.fire()
        #expect(fired == 10)          // fire is one-shot
    }

    @Test("cancel prevents the action from firing")
    func cancelStops() {
        let scheduler = ManualSettleScheduler()
        var fired = false
        scheduler.schedule(after: .milliseconds(400)) { fired = true }
        scheduler.cancel()
        scheduler.fire()
        #expect(fired == false)
    }
}
```

- [ ] **Step 4: Run the test**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/ManualSettleSchedulerTests`
Expected: PASS. (Also confirms the app target still builds with the new seam.)

- [ ] **Step 5: Commit**

```bash
git add Tables/Features/Game/SettleScheduling.swift TablesTests/ManualSettleScheduler.swift TablesTests/ManualSettleSchedulerTests.swift
git commit -m "Add SettleScheduling seam with real and manual schedulers"
```

---

### Task 3: Migrate to `onPartial`; move answer-aware settle + progress into the controller

This is one atomic change: the protocol, recognizer, fake, controller, and controller tests must move together to compile. It uses Task 1 (`SpokenNumber`/`VoiceProgress`) and Task 2 (`SettleScheduling`).

**Files:**
- Modify: `Tables/Services/AnswerRecognizing.swift`
- Modify: `Tables/Services/SpeechAnswerRecognizer.swift`
- Modify: `Tables/Features/Game/VoiceAnswerController.swift`
- Modify: `TablesTests/FakeAnswerRecognizer.swift`
- Rewrite: `TablesTests/VoiceAnswerControllerTests.swift`

**Interfaces:**
- Consumes: `SpokenNumber`, `VoiceProgress`, `SettleScheduling`/`TaskSettleScheduler` (Tasks 1–2); `GameSession` (`phase`, `fact.answer`, `submit(_:now:)`).
- Produces:
  - `AnswerRecognizing.onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)?` (replaces `onNumber`).
  - `VoiceAnswerController.init(session:recognizer:scheduler:now:)` (new `scheduler` param, defaulted) and `private(set) var progress: VoiceProgress?`.
  - `FakeAnswerRecognizer.emitPartial(_ number: Int?, isFinal: Bool)` (replaces `emit`).

- [ ] **Step 1: Rewrite the controller tests (RED)**

Replace the entire contents of `TablesTests/VoiceAnswerControllerTests.swift`:
```swift
import Testing
import Foundation
@testable import Tables

@MainActor
struct VoiceAnswerControllerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func make() -> (VoiceAnswerController, GameSession, FakeAnswerRecognizer, ManualSettleScheduler) {
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
        let scheduler = ManualSettleScheduler()
        let controller = VoiceAnswerController(
            session: session, recognizer: fake, scheduler: scheduler, now: { self.start }
        )
        return (controller, session, fake, scheduler)
    }

    @Test("syncToPhase starts listening while asking")
    func startsOnAsking() {
        let (controller, session, fake, _) = make()
        #expect(session.phase == .asking)
        controller.syncToPhase()
        #expect(fake.isListening)
        #expect(controller.display == .listening)
    }

    @Test("a terminal number submits immediately with no wait")
    func terminalSubmitsImmediately() {
        let (controller, _, fake, scheduler) = make()
        controller.syncToPhase()
        fake.emitPartial(7, isFinal: false)          // 7 is not extendable
        #expect(controller.display == .heard(7))
        #expect(fake.isListening == false)           // stopped on submit
        #expect(scheduler.lastDelay == nil)          // never scheduled a wait
        #expect(controller.progress == nil)
    }

    @Test("an extendable partial publishes progress and waits, choosing the delay by status")
    func extendableWaitsAndPublishes() {
        let (controller, session, fake, scheduler) = make()
        controller.syncToPhase()
        let answer = session.fact.answer
        // 20 is always extendable and never a ×3/×7 answer, so it isn't a match.
        fake.emitPartial(20, isFinal: false)
        let status = SpokenNumber.track(heard: 20, answer: answer)
        #expect(controller.progress == VoiceProgress(heard: 20, status: status))
        #expect(fake.isListening)                    // NOT submitted yet
        #expect(controller.display == .listening)
        let expected: Duration = status == .offTrack ? .milliseconds(400) : .milliseconds(1200)
        #expect(scheduler.lastDelay == expected)
    }

    @Test("firing the settle timer submits the pending number")
    func settleFiresSubmits() {
        let (controller, _, fake, scheduler) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)
        #expect(fake.isListening)                    // waiting
        scheduler.fire()
        #expect(controller.display == .heard(20))
        #expect(fake.isListening == false)
        #expect(controller.progress == nil)
    }

    @Test("a later terminal partial cancels the wait and submits the grown number")
    func laterTerminalCancelsWait() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)         // "twenty" — waiting
        fake.emitPartial(23, isFinal: false)         // "twenty three" — terminal
        #expect(controller.display == .heard(23))
        #expect(controller.progress == nil)
    }

    @Test("isFinal submits immediately")
    func isFinalSubmits() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: true)          // final transcript
        #expect(controller.display == .heard(20))
    }

    @Test("a late partial after submitting is ignored")
    func hasSubmittedBlocksLatePartial() {
        let (controller, _, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(7, isFinal: false)          // submits 7 -> phase leaves .asking
        fake.emitPartial(9, isFinal: false)          // ignored
        #expect(controller.display == .heard(7))
    }

    @Test("progress clears when the question leaves asking")
    func progressClearsOffAsking() {
        let (controller, session, fake, _) = make()
        controller.syncToPhase()
        fake.emitPartial(20, isFinal: false)
        #expect(controller.progress != nil)
        // Leave .asking without going through the controller's submit.
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)
        controller.syncToPhase()
        #expect(controller.progress == nil)
        #expect(controller.display == .idle)
    }

    @Test("a partial heard when not asking is ignored")
    func ignoresWhenNotAsking() {
        let (controller, session, fake, _) = make()
        controller.syncToPhase()
        let wrong = session.fact.answer == 1 ? 2 : 1
        session.submit(wrong, now: start)            // -> feedback
        controller.syncToPhase()                     // -> stop
        fake.emitPartial(99, isFinal: false)         // fake ignores (not listening)
        #expect(session.answered == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile / fail**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: FAIL — `emitPartial`, `scheduler:` init param, and `progress` don't exist yet.

- [ ] **Step 3: Change the protocol**

In `Tables/Services/AnswerRecognizing.swift`, replace the `onNumber` requirement:
```swift
@MainActor
protocol AnswerRecognizing: AnyObject {
    /// Fires for each recognition update while listening: the parsed number so
    /// far (`nil` if the transcript isn't yet a number) and whether the
    /// transcript is final. The consumer decides when to submit.
    var onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)? { get set }

    /// Request microphone + speech authorization. `granted` is true only when
    /// both are available. Safe to call repeatedly.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)

    /// Begin listening. Idempotent while already listening.
    func start()

    /// Stop listening and release the audio buffer.
    func stop()
}
```

- [ ] **Step 4: Strip the recognizer's settle logic and emit partials**

In `Tables/Services/SpeechAnswerRecognizer.swift`:

4a. Replace the stored callback property:
```swift
    var onNumber: ((Int) -> Void)?
```
with:
```swift
    var onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)?
```
And update the now-inaccurate class doc comment (it describes the old
fire-and-stop behaviour). Replace:
```swift
/// Forces `requiresOnDeviceRecognition` so nothing leaves the phone. Each
/// `start()` opens a fresh recognition request; the first partial transcript
/// that `SpokenNumberParser` resolves to a valid number fires `onNumber` once
/// and then the recogniser stops itself.
```
with:
```swift
/// Forces `requiresOnDeviceRecognition` so nothing leaves the phone. Each
/// `start()` opens a fresh recognition request and streams every parsed partial
/// up via `onPartial`; the controller owns the settle timing and decides when
/// to submit, then calls `stop()`.
```

4b. Delete the `didFire` machinery. Remove the stored property:
```swift
    private var didFire = false
```
and remove its assignment inside `start()` (the line `didFire = false`, just after `isRunning = true`). Then delete the settle-state block:
```swift
    /// A recognised number that might still be growing ("twenty" → "twenty
    /// one"), held until the stream settles rather than fired on the first
    /// partial. Cleared once it fires or the recogniser stops.
    private var pendingNumber: Int?
    private var settleTask: Task<Void, Never>?
    /// How long a still-growing number must go without a newer partial before it
    /// submits — long enough to bridge the gap between the words of a compound
    /// number, short enough to stay responsive. Tuned by ear on device.
    private static let settleInterval: Duration = .milliseconds(500)
```

4c. In `stop()`, delete the `cancelSettle()` call (the line `cancelSettle()` just after `wasListeningBeforeInterruption = false`).

4d. Replace the recognition-task callback body. Replace:
```swift
                guard let result else { return }
                let number = SpokenNumberParser.parse(result.bestTranscription.formattedString)
                if result.isFinal {
                    // The transcript is settled: submit the number now, or — if
                    // nothing parseable was heard (a run of silence) — restart so
                    // the question keeps listening rather than going deaf.
                    self.cancelSettle()
                    if let number {
                        self.fire(number)
                    } else {
                        self.restartListening()
                    }
                } else if let number, !self.isExtendable(number) {
                    // A number that can't grow by saying more ("forty two",
                    // "seven") — submit immediately.
                    self.cancelSettle()
                    self.fire(number)
                } else {
                    // Either an extendable number ("twenty", which may still
                    // become "twenty one") or any partial while one is pending:
                    // hold it and wait for the stream to go quiet, so a compound
                    // number isn't clipped to its prefix.
                    if let number { self.pendingNumber = number }
                    if self.pendingNumber != nil { self.armSettleTimer() }
                }
```
with:
```swift
                guard let result else { return }
                let number = SpokenNumberParser.parse(result.bestTranscription.formattedString)
                if result.isFinal {
                    // On a final transcript, hand up the number (if any). With no
                    // parseable number (a run of silence) keep listening rather
                    // than going deaf. The controller decides when to submit.
                    if number != nil {
                        self.onPartial?(number, true)
                    } else {
                        self.restartListening()
                    }
                } else {
                    // Stream every partial (number may be nil); the controller
                    // owns the answer-aware settle timing.
                    self.onPartial?(number, false)
                }
```

4e. Delete the helper methods `isExtendable(_:)`, `armSettleTimer()`, `cancelSettle()`, and `fire(_:)` entirely (the whole block from `private func isExtendable` through the end of `fire`, keeping the closing brace of the class). For reference, the deleted methods are:
```swift
    private func isExtendable(_ number: Int) -> Bool { ... }
    private func armSettleTimer() { ... }
    private func cancelSettle() { ... }
    private func fire(_ number: Int) { ... }
```

- [ ] **Step 5: Rewrite the controller with answer-aware settle + progress**

Replace the entire contents of `Tables/Features/Game/VoiceAnswerController.swift`:
```swift
import Foundation
import Observation

/// Bridges a `GameSession` to an `AnswerRecognizing` source, owning the
/// answer-aware settle timing.
///
/// It listens only while the question is `.asking`. A number that can't grow
/// (terminal) submits at once; a still-growing number is held for a settle
/// window whose length depends on whether it could still become the correct
/// answer — longer when on track, short when off track. All audio lives in the
/// recogniser; this controller is pure enough to test with a fake recogniser, a
/// seeded session, and a manual scheduler.
@MainActor
@Observable
final class VoiceAnswerController {

    enum Display: Equatable {
        case idle
        case listening
        case heard(Int)
    }

    private(set) var display: Display = .idle
    /// The latest heard number + on-track status while a number is settling;
    /// `nil` when nothing is mid-recognition. Published for the UI.
    private(set) var progress: VoiceProgress?

    private let session: GameSession
    private let recognizer: any AnswerRecognizing
    private let scheduler: any SettleScheduling
    private let now: () -> Date

    private var pendingNumber: Int?
    private var hasSubmitted = false

    private static let onTrackWait: Duration = .milliseconds(1200)   // .matches + .onTrack
    private static let offTrackWait: Duration = .milliseconds(400)

    init(session: GameSession,
         recognizer: any AnswerRecognizing,
         scheduler: any SettleScheduling = TaskSettleScheduler(),
         now: @escaping () -> Date = { Date() }) {
        self.session = session
        self.recognizer = recognizer
        self.scheduler = scheduler
        self.now = now
        self.recognizer.onPartial = { [weak self] number, isFinal in
            self?.considerPartial(number: number, isFinal: isFinal)
        }
    }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        recognizer.requestAuthorization(completion)
    }

    /// Call on appear and whenever `session.phase` changes.
    func syncToPhase() {
        if session.phase == .asking {
            if display != .listening {
                resetForNewQuestion()
                display = .listening
                recognizer.start()
            }
        } else {
            stop()
        }
    }

    /// Release the recogniser when the view goes away or the child opts out of
    /// voice — no phase change fires on view teardown.
    func stopListening() {
        stop()
    }

    private func considerPartial(number: Int?, isFinal: Bool) {
        guard session.phase == .asking, !hasSubmitted else { return }

        if isFinal {
            if let number { submit(number) }        // else: recogniser restarts itself
            return
        }

        if let number, !SpokenNumber.isExtendable(number) {
            submit(number)                          // terminal = complete answer
            return
        }

        if let number { pendingNumber = number }    // extendable candidate

        guard let pending = pendingNumber else { return }
        let status = SpokenNumber.track(heard: pending, answer: session.fact.answer)
        progress = VoiceProgress(heard: pending, status: status)
        let wait = status == .offTrack ? Self.offTrackWait : Self.onTrackWait
        scheduler.schedule(after: wait) { [weak self] in
            self?.settleFired()
        }
    }

    private func settleFired() {
        guard session.phase == .asking, !hasSubmitted, let pending = pendingNumber else { return }
        submit(pending)
    }

    private func submit(_ number: Int) {
        hasSubmitted = true
        pendingNumber = nil
        progress = nil
        scheduler.cancel()
        display = .heard(number)
        recognizer.stop()
        session.submit(number, now: now())
    }

    private func resetForNewQuestion() {
        hasSubmitted = false
        pendingNumber = nil
        progress = nil
        scheduler.cancel()
    }

    private func stop() {
        scheduler.cancel()
        pendingNumber = nil
        progress = nil
        guard display != .idle else { return }
        display = .idle
        recognizer.stop()
    }
}
```

- [ ] **Step 6: Update the fake recognizer**

In `TablesTests/FakeAnswerRecognizer.swift`, replace the `onNumber` property:
```swift
    var onNumber: ((Int) -> Void)?
```
with:
```swift
    var onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)?
```
and replace `emit`:
```swift
    /// Simulate the recogniser hearing a number. No-op unless listening,
    /// mirroring the real recogniser which only emits between start/stop.
    func emit(_ number: Int) {
        guard isListening else { return }
        onNumber?(number)
    }
```
with:
```swift
    /// Simulate a recognition partial. No-op unless listening, mirroring the
    /// real recogniser which only emits between start/stop.
    func emitPartial(_ number: Int?, isFinal: Bool) {
        guard isListening else { return }
        onPartial?(number, isFinal)
    }
```

- [ ] **Step 7: Run the controller tests (GREEN)**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests/VoiceAnswerControllerTests`
Expected: PASS.

- [ ] **Step 8: Build the whole app and run the full unit suite**

Run: `xcodebuild build -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17'`
Expected: BUILD SUCCEEDED (no other consumer of `onNumber`/`emit` remains; `VoiceInputView` uses the controller, whose public surface is unchanged apart from the additive `progress`).
Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TablesTests`
Expected: all unit suites PASS.

- [ ] **Step 9: Commit**

```bash
git add Tables/Services/AnswerRecognizing.swift Tables/Services/SpeechAnswerRecognizer.swift Tables/Features/Game/VoiceAnswerController.swift TablesTests/FakeAnswerRecognizer.swift TablesTests/VoiceAnswerControllerTests.swift
git commit -m "Move answer-aware settle and progress event into VoiceAnswerController"
```

---

### Task 4: Manual device verification

**Files:** none (verification only). No commit unless a fix is needed.

On a real iPhone that supports on-device recognition, in voice mode:

- [ ] **Step 1:** Pick a question with a compound answer (e.g. 36). Say the full answer ("thirty six") — confirm it submits **36** promptly (as soon as the terminal number is heard).
- [ ] **Step 2:** For the same question, say only "thirty" and stop — confirm it waits noticeably (~1.2 s) before submitting 30, giving time to finish.
- [ ] **Step 3:** Say a clearly-wrong compound number ("forty two" for answer 36) — confirm it submits 42 with only the short (~0.4 s) wait, not the long one.
- [ ] **Step 4:** Terminal answers (7, 42) and single tens that equal the answer still feel responsive.
- [ ] **Step 5:** Confirm nothing regressed from the earlier voice fixes: interruptions/backgrounding recovery, and no premature clipping of compound numbers.
- [ ] **Step 6:** (Optional, once UI consumes it) confirm `controller.progress` reflects the heard number + status during the wait.

If the 1200/400 ms feel wrong, they are the `onTrackWait` / `offTrackWait` constants in `VoiceAnswerController`.

---

## Notes for the implementer

- `GameSession` is not modified. The seam remains `session.submit(_:now:)`.
- Tasks 1 and 2 are independent and leave the app building. Task 3 is the atomic migration — the protocol change means the recognizer, controller, and fake must all land together; verify with the controller suite then the full unit suite.
- The controller's delay-branch test asserts against `SpokenNumber.track` as the oracle (whichever branch the seeded answer produces for `20`); the exhaustive on-track/off-track semantics are covered with literal answers in `SpokenNumberTests`.
- `VoiceInputView` needs no change: the controller's init gained a defaulted `scheduler` param, and `progress` is additive and unused by the view for now (UI handling is out of scope).
