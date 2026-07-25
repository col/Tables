# Adjustable Voice Speed Setting — Design

**Date:** 2026-07-25
**Status:** Approved
**Builds on:** `2026-07-25-voice-answer-aware-settle-design.md`

## Summary

Add a Settings control that lets the user tune how quickly voice recognition
submits an answer — a 5-notch native slider from **Fastest** to **Slowest**. Each
notch sets the two settle durations the voice controller already uses:

| Notch | short wait | on-track wait |
|---|---|---|
| Fastest | 200 ms | 600 ms |
| Fast | 300 ms | 700 ms |
| Normal (default) | 400 ms | 800 ms |
| Slow | 500 ms | 900 ms |
| Slowest | 600 ms | 1000 ms |

(short = the wait for a match / off-track number; on-track = the longer patience
while the child is heading toward the answer.) These replace the currently
hardcoded `shortWait` (400) / `onTrackWait` (1200) constants — note the on-track
values come down, per intent, and will be tuned further via manual testing.

## Product decisions

- **Control:** a native SwiftUI `Slider` snapped to 5 discrete steps, with the
  current notch label shown and Fastest/Slowest end labels.
- **Default:** `.normal` (400 / 800).
- **Placement:** a new card in `SettingsView`, shown **only when the device
  supports voice** (`SpeechAnswerRecognizer.isSupported`), consistent with how
  voice is hidden elsewhere on unsupported devices.
- **Application:** the selected speed is read once per game when the controller
  is built (settings aren't changed mid-question); a new game picks up a change.
- **Mapping rule is unchanged:** `.onTrack → onTrackWait`; `.matches` / `.offTrack
  → shortWait`; a terminal number still submits immediately.

## Components

### `VoiceSpeed` — new pure type (`Tables/Model/VoiceSpeed.swift`, `nonisolated`)

Int-backed so it maps directly onto the slider and persists as a small integer.
```swift
enum VoiceSpeed: Int, CaseIterable, Codable, Sendable {
    case fastest, fast, normal, slow, slowest   // rawValue 0…4

    var label: String            // "Fastest" … "Slowest"
    var shortWait: Duration      // 200 / 300 / 400 / 500 / 600 ms
    var onTrackWait: Duration    // 600 / 700 / 800 / 900 / 1000 ms
}
```
`CaseIterable` order is fastest→slowest (matching rawValue), so the slider range
is `0…(VoiceSpeed.allCases.count - 1)`.

### `AppSettings` — new persisted property

Following the existing `didSet`-persist pattern:
```swift
private static let voiceSpeedKey = "settings.voiceSpeed"
var voiceSpeed: VoiceSpeed { didSet { defaults.set(voiceSpeed.rawValue, forKey: Self.voiceSpeedKey) } }
```
Loaded in `init` from the stored Int, defaulting to `.normal` when unset or when
the stored value isn't a valid case.

### `SettingsView` — the slider card

A new `Card` after the multiple-choice card, gated on
`SpeechAnswerRecognizer.isSupported`:
- Title "Voice speed" + description "How long voice waits for you to finish
  speaking." + the current `settings.voiceSpeed.label` on the trailing side.
- A `Slider(value:in:step:)` over `0...Double(VoiceSpeed.allCases.count - 1)`
  step `1`, tinted `Color.sage`, bound through a computed `Binding<Double>` that
  reads `voiceSpeed.rawValue` and writes back `VoiceSpeed(rawValue: Int(value.rounded())) ?? .normal`.
- "Fastest" / "Slowest" end labels below the track.

### `VoiceAnswerController` — speed-driven durations

- `init` gains `speed: VoiceSpeed = .normal` (stored).
- The static `onTrackWait` / `shortWait` constants are removed; the pick becomes
  `let wait = status == .onTrack ? speed.onTrackWait : speed.shortWait`.

### `VoiceInputView` — pass the setting in

Gains `@Environment(AppSettings.self) private var settings` and constructs the
controller with `speed: settings.voiceSpeed`.

## Testing strategy

- **`VoiceSpeedTests`** (pure): each case's `shortWait` / `onTrackWait` / `label`
  matches the table; `allCases` order is fastest→slowest.
- **`AppSettingsTests`**: `voiceSpeed` persists and round-trips through a fresh
  `AppSettings`; unset → `.normal`; an out-of-range stored Int → `.normal`.
- **`VoiceAnswerControllerTests`**: updated to the new default (`.normal` → on-track
  **800 ms**, match/off-track **400 ms**); a new test injects `.fastest` and asserts
  200 / 600, proving the speed wiring end-to-end through the settle.
- **`SettingsView`** slider: verified by build + the manual device pass (visual +
  that changing it actually changes the felt speed).

## Out of scope (YAGNI)

- Applying a speed change to an in-progress game.
- Per-answer-mode or per-table speed.
- Any change to the parser, recognizer, or `GameSession`.
