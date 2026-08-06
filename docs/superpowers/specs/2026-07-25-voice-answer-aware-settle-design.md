# Answer-Aware Voice Settle + Progress Event — Design

**Date:** 2026-07-25
**Status:** Approved
**Builds on:** `2026-07-24-voice-answer-mode-design.md`

## Summary

Make the voice-mode settle window *answer-aware*, and publish a progress event
the UI can observe while a number is still being spoken.

Today a still-growing number (e.g. "thirty…") is held for a single fixed 400 ms
settle before it submits, so a compound number isn't clipped to its prefix. This
change makes the wait depend on whether what we've heard could still become the
correct answer:

- **On track** (could still reach the correct answer) → wait **longer** (1200 ms),
  giving the child time to complete a correct answer.
- **Off track** (can't reach the correct answer) → wait the current **short**
  400 ms, since we already know the answer will be wrong.

It also publishes an observable `progress` event carrying the number heard so far
and its on-track status, so the UI can react during the wait. **UI handling is out
of scope for this change** — we only publish the event.

## Product decisions

- **"On track" = could still reach the exact correct answer**, as a spoken-prefix
  relationship on each number's canonical words: "thirty" (30) is on-track for 36
  (→"thirty six"); "forty" (40) and "three" (3) are not. This distinguishes cases
  a purely-arithmetic heuristic cannot (3 vs 30 both `< 36`).
- **Durations:** on-track **1200 ms**; a **match** or off-track **400 ms**
  (tunable constants). A terminal number (one that can't grow, e.g. 36, 42, 7)
  still submits immediately. (Refinement after first device testing: a `.matches`
  originally shared the 1200 ms wait, but since it's already the correct answer
  it now takes only the short insurance window — long enough to catch it growing
  into a wrong number like "thirty" → "thirty two", but no full-patience wait.)
- **Event payload:** `VoiceProgress { heard: Int, status: .matches | .onTrack |
  .offTrack }`. No transcript string.
- **Event mechanism:** an observable `private(set) var progress: VoiceProgress?`
  on `VoiceAnswerController` (the `@Observable` state pattern already used
  throughout the UI). `nil` when nothing is mid-recognition.
- **Where the answer-aware logic lives:** in `VoiceAnswerController`, which knows
  the expected answer (`session.fact.answer`). The settle timer moves out of the
  recognizer and up into the controller. `GameSession` stays untouched.

## Architecture

The answer-aware duration, the on-track judgment, and the progress event all need
the expected answer — which the controller has and the recognizer does not. So the
recognizer stops owning the wait and becomes a pure partial stream; the controller
owns the timing.

```
audio → SpeechAnswerRecognizer → onPartial(number:isFinal:) → VoiceAnswerController
          (pure speech)              (per recognition callback)     ├─ answer-aware settle timing
                                                                     ├─ progress: VoiceProgress?   → view
                                                                     └─ session.submit(_:now:)     → GameSession
```

### New pure types (Model, `nonisolated`, unit-tested)

```swift
struct VoiceProgress: Equatable, Sendable {
    enum Status: Equatable, Sendable { case matches, onTrack, offTrack }
    let heard: Int
    let status: Status
}

enum SpokenNumber {
    /// Canonical words for an answer number, reconstructed from the Int (the
    /// inverse of SpokenNumberParser). 36 -> ["thirty","six"].
    static func words(_ n: Int) -> [String]
    /// Could this number still grow if the child keeps speaking? (Moved
    /// verbatim from SpeechAnswerRecognizer.) 20/100/1 -> true; 7/42 -> false.
    static func isExtendable(_ n: Int) -> Bool
    /// Status of a heard number against the expected answer.
    static func track(heard: Int, answer: Int) -> VoiceProgress.Status
}
```

`words` takes the **Int** the recognizer emits and reconstructs the canonical
spoken words purely as an internal step — the transcript text is never needed.

### `SpeechAnswerRecognizer` (speech only)

Loses the settle machinery: `pendingNumber`, `settleTask`, `settleInterval`,
`isExtendable`, `armSettleTimer`, `cancelSettle`, `fire`, `didFire`. Keeps audio,
the generation guard, interruption recovery, restart-on-silence, authorization,
and `start()`/`stop()`.

Protocol change on `AnswerRecognizing`:
`onNumber: ((Int) -> Void)?` → `onPartial: ((_ number: Int?, _ isFinal: Bool) -> Void)?`

Callback becomes:
```swift
guard generation == self.generation else { return }
if error != nil { self.stop(); return }
guard let result else { return }
let number = SpokenNumberParser.parse(result.bestTranscription.formattedString)
if result.isFinal {
    if number != nil { self.onPartial?(number, true) }
    else { self.restartListening() }        // silence — keep listening
} else {
    self.onPartial?(number, false)          // stream every partial (number may be nil)
}
```
The recognizer no longer self-stops on a number; the **controller** stops it on
submit / phase change.

### `VoiceAnswerController` (game-aware)

Gains: `progress`, `pendingNumber`, the settle timer (via an injected scheduler,
below), the answer-aware durations, and the submit decision. Its recognizer hook
changes from `onNumber` to `onPartial`.

New state:
```swift
private(set) var progress: VoiceProgress?
private var pendingNumber: Int?
private var hasSubmitted = false            // one submit per question
private static let onTrackWait: Duration = .milliseconds(1200)   // onTrack only
private static let shortWait:   Duration = .milliseconds(400)    // matches or offTrack
```

Per-partial logic (`considerPartial(number:isFinal:)`):
```
guard session.phase == .asking, !hasSubmitted else { return }

if isFinal:
    cancelSettle(); if let n { submit(n) }; return

if let n, !SpokenNumber.isExtendable(n):    // terminal = complete answer
    cancelSettle(); submit(n); return

if let n { pendingNumber = n }              // extendable candidate

if let pending = pendingNumber {            // still-growing: publish + (re)arm
    let status = SpokenNumber.track(heard: pending, answer: session.fact.answer)
    progress = VoiceProgress(heard: pending, status: status)
    scheduler.schedule(after: status == .onTrack ? Self.onTrackWait : Self.shortWait) {
        [weak self] in self?.settleFired()
    }
}
```
- `settleFired()`: if still `.asking` and `pendingNumber != nil`, `submit(pending)`.
- `submit(n)`: `hasSubmitted = true`, `progress = nil`, `display = .heard(n)`,
  `recognizer.stop()`, `session.submit(n, now())`.
- Reset on `syncToPhase()` entering `.asking`: `hasSubmitted = false`,
  `pendingNumber = nil`, `progress = nil`, cancel the scheduler.
- `stopListening()`/stop also clear `progress`, `pendingNumber`, and cancel.

### Settle scheduler seam (testability)

The settle timer is behind a tiny protocol so tests run without real time:
```swift
@MainActor protocol SettleScheduling: AnyObject {
    /// Run `action` after `delay`, cancelling any previously-scheduled action.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
    func cancel()
}
```
- **Real:** `TaskSettleScheduler` — cancels the prior `Task`, starts
  `Task.sleep(for: delay)`, runs `action` on completion.
- **Test:** `ManualSettleScheduler` — records `lastDelay` and the pending
  `action`; `fire()` invokes it. Lets tests assert the chosen duration
  (1200 vs 400) and simulate the settle firing, with no sleeping.

`VoiceAnswerController.init` takes `scheduler: any SettleScheduling =
TaskSettleScheduler()` alongside the existing `now:` clock.

## Behavior (answer = 36)

| child says | partials → controller | outcome |
|---|---|---|
| "thirty six" | 30 (extendable, onTrack) then 36 (terminal) | `progress=(30,.onTrack)`, arm 1200 ms; 36 arrives → `submit(36)`, `progress=nil`. Fires as soon as 36 heard. |
| "thirty" (stops) | 30 (extendable, onTrack) | `progress=(30,.onTrack)`, 1200 ms quiet → `submit(30)`. |
| "forty two" | 40 (extendable, offTrack) then 42 (terminal) | `progress=(40,.offTrack)`, arm 400 ms; 42 → `submit(42)`. Short patience. |
| "seven" | 7 (terminal) | `submit(7)` immediately, no progress. |

`progress` is non-nil exactly during the settle window and clears the instant we
submit.

## Testing strategy

Approach A makes the whole feature unit-testable (no hardware).

**`SpokenNumber` — pure tests:**
- `words`: 3, 30, 36, 100, 144 canonical decompositions.
- `track`: answer-36 table (36→.matches, 30→.onTrack, 3→.offTrack, 40→.offTrack,
  42→.offTrack) and hundreds (answer 144: 1/100/140→.onTrack, 120→.offTrack).
- `isExtendable`: regression tests carried over from the recognizer.

**`VoiceAnswerController` — `FakeAnswerRecognizer` + seeded `GameSession` +
`ManualSettleScheduler`:**
- Terminal number submits immediately, no progress.
- On-track extendable publishes `(n, .onTrack)`, does not submit until settle;
  `scheduler.lastDelay == 1200 ms`.
- Off-track extendable publishes `(n, .offTrack)`; `scheduler.lastDelay == 400 ms`.
- A following terminal partial cancels the wait and submits.
- `scheduler.fire()` on a pending number submits it.
- `isFinal` submits immediately; a late partial after submit is blocked by
  `hasSubmitted`.
- `progress` clears on submit and on leaving `.asking`.

**Not unit-tested (hardware, manual on device):** real streaming partials, the
`TaskSettleScheduler` real timing, and how the tuned 1200/400 ms feel.

## Out of scope (YAGNI)

- Any UI consumption of `progress` (coloring, hints, animation).
- The transcript string in the payload.
- More than two wait tiers.
- Changing the parser or `GameSession`.
