# Voice Answer Mode — Design

**Date:** 2026-07-24
**Status:** Approved

## Summary

Add a third answer mode to the Tables game: answering by voice. When a game
uses voice mode, the microphone listens the whole time a question is shown; as
soon as the child speaks a number, it is recognised on-device and submitted
immediately — the same submission path the number pad already uses. Voice sits
alongside the existing Multiple choice and Number pad modes.

Motivation is broad: faster answering for younger / pre-writing children,
hands-free out-loud recall (flashcard-style), an accessibility option for kids
who struggle with tile/keypad input, and novelty that keeps practice engaging.

## Product decisions

- **Third answer mode.** `AnswerMode.voice`, chosen on the setup screen like the
  existing modes.
- **Always listening, auto-submit.** No button. The mic listens while a question
  is shown and submits the first confidently-recognised number.
- **Instant submit.** Submit the moment a valid number resolves — no confirmation
  step. The game's countdown mode is already forgiving (a wrong answer simply
  re-asks the same question), so a rare mis-hear is low-cost.
- **On-device only.** `requiresOnDeviceRecognition = true`. No audio leaves the
  phone, works offline, and avoids privacy-disclosure/COPPA concerns for a
  children's-category app. Recognising single numbers is well within on-device
  accuracy.
- **Hide when unsupported; keypad fallback on denial.** The voice option only
  appears in setup when the device supports on-device recognition. Permission is
  requested on first voice game. If mic/speech permission is denied, an in-game
  notice offers **Open Settings** or **Use keypad**, so a child is never blocked.

## Architecture & boundaries

Five units, each with one job. The central constraint: **`GameSession` does not
change.** All audio and real-time state live in the view/service layer; the
session still receives only `submit(value, now:)`. Parsing and game logic remain
testable without hardware.

### 1. `SpokenNumberParser` — pure value type (`Tables/Model/`)

```
func parse(_ transcript: String) -> Int?
```

Turns a recognised transcript into a number, or `nil`. No audio, no iOS speech
types — just `String -> Int?`. Fully unit-tested.

Handles:
- Word forms: `"forty-two"`, `"forty two"`, `"four two"` → 42; `"forty"` → 40;
  `"one hundred forty-four"` → 144.
- Digits / mixed: `"42"`, `"7"`, `"0"`.
- Kid homophones: `"to"/"too"` → 2, `"for"` → 4, `"ate"` → 8, `"free"/"tree"` → 3.
- Extraction from a phrase: `"um forty two"`, `"the answer is 42"` → 42.
- Range guard: constrained to the plausible answer range **1–144**. Out-of-range
  or noise (`"banana"`, `"two hundred"`, `"1000"`) → `nil`, so junk resolves to
  nothing rather than a wrong guess.

### 2. `SpeechAnswerRecognizer` — service (`Tables/Services/`, behind a protocol)

Wraps `SFSpeechRecognizer` + `AVAudioEngine`. Forces on-device recognition.

Protocol so views/tests can run against a fake (no real mic):

```
protocol AnswerRecognizing {
    var state: RecognizerState { get }          // observable
    func start()
    func stop()
    // fires once when a valid number resolves
    var onNumber: ((Int) -> Void)? { get set }
}

enum RecognizerState { case idle, listening, heard(Int) }
```

Responsibilities:
- Configure `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
- Run `AVAudioEngine`, feed the buffer to a recognition request, receive
  streaming partial transcripts.
- On each partial, run `SpokenNumberParser`. The first partial that resolves to a
  valid number fires `onNumber` **exactly once**, transitions to `.heard(n)`,
  then `stop()`s — no double-fire on subsequent partials. A fresh recognition
  request is created per question.
- Own audio-session setup/teardown and authorization checks.
- `SFSpeechRecognizer` callbacks arrive off the main actor; hop back to
  `@MainActor` before touching observable state or calling `GameSession`.

### 3. `VoiceInputView` — SwiftUI (`Tables/Features/Game/`)

The `.voice` branch of `GameView` (alongside `MultipleChoiceView` /
`NumberPadView`). Owns a `SpeechAnswerRecognizer`.

- Large, calm mic indicator that pulses while `.listening`; respects
  `accessibilityReduceMotion` (already read by `GameView`).
- On a resolved number, a brief "heard: N" flash in the same entry-display style
  as the number pad, echoing sage/blush on correct/wrong via `session.phase`, so
  voice feels visually consistent with the other modes.
- Reuses `DesignSystem` components (Card / Typography / Palette / Metrics).
- No buttons. A small first-timer hint ("Say your answer").
- On a recognised number, calls `session.submit(value, now: Date())` — the exact
  seam `NumberPadView` uses.

### 4. `AnswerMode.voice` — enum case + setup gating + persistence

- New case with `title` / `subtitle` (e.g. "Voice" / "Say the answer").
- `SetupView`'s answer-mode section shows the voice row **only when**
  `SFSpeechRecognizer.supportsOnDeviceRecognition` is true for the locale and
  speech isn't restricted.
- Persistence (`SetupModel`) guards against a stored `.voice` value on a device
  that can't support it, falling back to `.multipleChoice`.

### 5. Info.plist permissions

- `NSMicrophoneUsageDescription` — "Tables listens so you can say your answers
  out loud."
- `NSSpeechRecognitionUsageDescription` — "Tables turns what you say into your
  answer. Speech is processed on your device."

## Lifecycle & game-phase wiring

The recognizer is driven off `session.phase` by `VoiceInputView`:

| Game phase | Recognizer |
|---|---|
| `.asking` | `start()` → `.listening` |
| number resolved | `onNumber` → view calls `submit`; recognizer `stop()` |
| `.feedback(...)` / `.reviewing` holds | `.idle` (no listening during praise / "try again") |
| next question (`nextQuestion`) | phase back to `.asking` → `start()` |
| `.reviewing` → `tryAgain` | back to `.asking` → `start()` |
| `.finished` | `stop()`, tear down audio session |

- **Scene phase:** background → `stop()` + deactivate audio session; foreground
  while `.asking` → `start()`. Rides on `GameView`'s existing `scenePhase`
  handling that already pauses/resumes the session.
- **Audio session:** `.playAndRecord` so the existing correct/incorrect
  `FeedbackPlayer` sounds still play while the mic is active. Coexistence with
  `FeedbackPlayer` to be verified during implementation.

## Permission flow (first voice game)

Requested when a voice game actually starts, so the ask has context. Two grants:
speech recognition (`SFSpeechRecognizer.requestAuthorization`) and microphone
(`AVAudioApplication.requestRecordPermission`).

- **Granted** → listening begins.
- **Denied** → in-game notice: "Voice needs microphone access", with **Open
  Settings** and **Use keypad** (switches this game to `NumberPadView`).

## Testing strategy

Everything risky sits behind a seam reachable without a microphone.

**`SpokenNumberParser` — pure unit tests (bulk of coverage):**
word forms, digits/mixed, kid homophones, phrase extraction, and range-guard
rejections (all cases listed under unit 1).

**`SpeechAnswerRecognizer` — via `AnswerRecognizing` + a `FakeAnswerRecognizer`:**
`start()` → `.listening`; feeding a parseable transcript → `.heard(n)` and
`onNumber` fires exactly once; `stop()` → `.idle`; a second partial after a hit
does not double-fire.

**`VoiceInputView` + session integration:**
drive a real `GameSession` (seeded generator, injected clock — as existing tests
do) with the fake recognizer. A recognised number produces the same outcome as a
keypad entry: correct advances/scores; wrong re-asks in countdown, reveals in
revision. Phase wiring: listener starts on `.asking`, idle during feedback holds,
restarts on next question and `tryAgain`.

**Gating / persistence:**
voice row hidden when on-device recognition unsupported; a stored `.voice` mode
on an unsupported device falls back to `.multipleChoice`.

**Manual (documented, not unit-tested):** real `SFSpeechRecognizer` accuracy, mic
capture, and live permission dialogs — verified by hand on device. Simulator
speech support is unreliable, so on-device testing is the checkpoint.

## Out of scope (YAGNI)

- Server-based recognition / accuracy fallback.
- Confirmation / correction step before submit.
- Voice for anything other than answering (no voice navigation/menus).
- Non-English locales beyond what on-device recognition handles for the device
  locale.
