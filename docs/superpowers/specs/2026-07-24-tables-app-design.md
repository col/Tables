# Tables — Design Spec

**Date:** 2026-07-24
**Status:** Approved

An iOS app that helps children practise their times tables. Calm, quiet, and
free of the mascots, confetti and noise that dominate the category — closer to
the NYT Games app than to a typical kids' maths game.

---

## 1. Product

**Audience:** primary-school children (whole age range), plus the adult holding
the phone.

**Scope:** multiplication only, tables 1–12 against multipliers 1–12.

**No login.** The app opens straight onto the home screen after install. All
data is local to the device; nothing is uploaded and no account exists.

**Source of truth for design:** the Claude Design project
`Times tables practice app` (`4df9b49e-986b-4fe2-8484-35933c63854e`), file
`Tables App.dc.html`, and the token set under
`_ds/tables-design-system-61e80556-1816-472a-8fdf-9bf97e9c4f22/`. Where this
spec and the prototype disagree, this spec wins; every such divergence is
called out explicitly below.

### Game modes

**Countdown** — how many correct answers can they give before the clock runs
out. Time limits: 30, 60, 90, 120 seconds.

**Revision** — no timer. Questions are chosen with a bias toward facts the
child has historically been slow to answer. Lengths: 10, 20, 30, 40, 50, 60
questions, or Endless.

### Answer modes

**Multiple choice** — a grid of tiles, one correct. Count is a user setting: 4
(2×2) or 6 (2×3), defaulting to 6.

**Number pad** — a custom in-app pad. Never the system keyboard, so the app's
typography and spacing hold throughout.

**Voice** — out of scope for v1. It appears in the Answer mode list, greyed,
with a "Soon" chip, exactly as the prototype shows it.

---

## 2. Platform

| | |
|---|---|
| Deployment target | iOS 26.0 |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`) |
| Orientation | Portrait only, both idioms |
| Appearance | Light only (`UIUserInterfaceStyle = Light`) |
| Bundle id | `com.challengr.Tables` (unchanged) |
| Persistence | SwiftData |
| Unit tests | Swift Testing |
| UI tests | XCTest |

Appearance is locked to light because the token set defines only the warm-paper
light palette. There are no dark values to map, so a device in dark mode would
otherwise render a half-inverted app. Dark mode requires a designed second
palette and is out of scope.

On iPad the content is capped at a **420pt centred column** on the app canvas,
so the layout reads as designed rather than as a stretched phone.

---

## 3. Architecture

Three layers. The game rules are deliberately free of both SwiftData and
SwiftUI so they can be exercised as plain values in unit tests.

```
Tables/
  TablesApp.swift
  DesignSystem/
    Palette.swift          Colour tokens
    Typography.swift       Font tokens
    Metrics.swift          Spacing, radii, strokes
    Motion.swift           Durations, easing, Reduce Motion
    Components/            TileButton, PillButton, Card, Eyebrow,
                           BackButton, BrandMark, Chip
  Model/
    Fact.swift             struct Fact { a, b }, answer
    GameMode.swift         countdown | revision
    AnswerMode.swift       multipleChoice | numberPad
    GameLength.swift       countdown seconds | question count | endless
    GameConfig.swift       tables + answerMode + length, configKey
    FactStat.swift         @Model
    GameRun.swift          @Model
    ProgressRepository.swift
    QuestionPicker.swift   pure
    DistractorGenerator.swift  pure
    Mastery.swift          pure
    ScoreBoard.swift       pure
  Game/
    GameSession.swift      @Observable state machine
  Features/
    Home/ Setup/ Game/ Results/ Progress/ Settings/
  Services/
    Haptics.swift
    SoundPlayer.swift
    AppSettings.swift
  Resources/Fonts/         3 static TTFs
```

`GameSession` depends on a `ProgressRecording` protocol, never on
`ModelContext`. A complete game — timer, scoring, feedback timing, termination
— can therefore be driven in a test against an in-memory recorder with no
model container and no simulator.

Anything random (`QuestionPicker`, `DistractorGenerator`) takes an injected
`RandomNumberGenerator`, so tests are deterministic.

---

## 4. Data model

### FactStat (SwiftData)

```swift
@Model final class FactStat {
    var key: String            // "7x8", unique
    var a: Int
    var b: Int
    var attempts: Int          // every submitted answer, right or wrong
    var correctCount: Int
    var averageMillis: Double  // EMA over correct answers only
    var lastAnsweredAt: Date
}
```

`averageMillis` is an exponential moving average with **α = 0.3**, updated on
correct answers only:

```
averageMillis = 0.3 × latestMillis + 0.7 × averageMillis
```

On the first correct answer it is set directly to `latestMillis`. Using an EMA
rather than a running mean means the figure tracks the child's current ability
instead of being anchored by early fumbling — a fact they have since mastered
stops looking slow. One stored field, no arrays, no migration risk.

Incorrect answers increment `attempts` and update `lastAnsweredAt` but do not
touch `averageMillis`.

### GameRun (SwiftData)

```swift
@Model final class GameRun {
    var configKey: String
    var score: Int       // correct answers
    var answered: Int    // questions completed
    var date: Date
}
```

### When timings are recorded

Both modes feed `FactStat`, so the mastery grid fills from normal play rather
than only from Revision.

- **Revision** — records the time from question appearing to answer submitted,
  right or wrong.
- **Countdown** — records a time **only when the first attempt is correct**. If
  the first attempt is wrong, `attempts` increments but no time is ever
  recorded for that question, even once they get it right. Retry loops
  therefore cannot poison the timing data.

*Divergence from prototype: it records timings in Revision only.*

---

## 5. Game logic

### Question selection

**Countdown** — uniform random over every fact in the selected tables
(`a ∈ selected tables`, `b ∈ 1…12`).

**Revision** — two phases:

1. **Unseen first.** Every fact in the selected tables with `attempts == 0` is
   served first, in random order. This guarantees coverage: a child cannot
   finish a 60-question session having never been shown ×7.
2. **Weighted.** Once no unseen facts remain, weighted random selection with
   `weight = max(400, averageMillis)`. Slower facts surface more often.

In both modes, a fact never repeats immediately after itself (unless the
selected pool contains only one fact).

*Divergence from prototype: it gives unseen facts a flat 1600ms default weight,
which lets facts the child is merely slow at starve facts they have never
seen.*

### Distractor generation

Carried over from the prototype, parameterised by option count (4 or 6):

```
candidate = answer + (random(0…6) − 3) × (coinFlip ? 1 : a)
```

This produces a mix of off-by-small errors and same-table multiples — both
plausible mistakes, which is what makes the choice meaningful. Candidates must
be positive and distinct from the answer and from each other. If the loop runs
short, pad upward with `answer + n`. The final set is shuffled.

### Answering

When an answer is **correct**, the answer settles in beside the question — the
problem slides left and "= 56" fades in — so the child always sees the whole
fact written out. Implemented with `Fact.answerReveal` and a `revealAnswer`
flag on the session.

**Countdown**
- Correct → the answer reveals inline, praise pill, score +1, brief pause,
  cross-fade to next question.
- Wrong → "Not quite — try again" pill, the answer is **not** revealed, the
  question stays and they retry. Time is the only penalty, so the score
  remains a clean count of correct answers.

**Revision**
- Correct → the answer reveals inline, praise pill, score +1, advance after a
  pause.
- Wrong → the answer reveals inline (in multiple choice the correct tile also
  turns sage, the chosen tile turns blush) and a **"Try again"** button
  appears. There is no auto-advance: the question is not counted and does not
  move on until it is answered correctly. "Try again" re-presents the same
  question, regenerating the multiple-choice options. A question first missed
  and only later answered correctly is recorded untimed — the same
  "retry proves knowledge, not speed" rule as Countdown.

*Divergence from prototype: the earlier build revealed the fact in a feedback
pill and auto-advanced on a wrong Revision answer. The reveal is now inline and
a wrong Revision answer waits for "Try again".*

Praise is drawn from a fixed set — "Nice!", "Correct!", "Well done!", "Great!",
"Yes!", "Spot on!", "Brilliant!", "Perfect!", "That's it!", "Lovely!". No
emoji, ever. That is a brand rule, not a preference.

Timing constants, from the prototype: 750ms correct hold (Countdown), 850ms
wrong hold (Countdown), 1300ms hold (correct Revision), 240ms cross-fade, 460ms
answer reveal.

### Termination

- **Countdown** — clock reaches zero.
- **Revision, fixed length** — `answered` (correct answers) reaches the chosen
  count.
- **Revision, Endless** — runs until the child leaves with the back button.

There is no in-game "End session" button. The back button abandons the run
without recording it. Because there is no early-finish, Endless Revision never
reaches the results screen — it is open-ended practice.

*Divergence from prototype: the "End session / Finish" button has been removed.*

### Countdown timer

Deadline-based, not a decrementing counter, so it stays accurate under drift.

**Backgrounding pauses the clock** and resumes on return to foreground. A child
interrupted by something outside their control should not lose their run.
Implemented by tracking the remaining interval on `scenePhase` change.

The timer pill turns blush for the final 10 seconds.

---

## 6. Scoring and best runs

`configKey = "\(mode)|\(sortedTables)|\(answerMode)|\(length)"`

Best runs are scoped to the **exact configuration**. Only like-for-like runs
compare: a 120-second all-tables run is not comparable to a 30-second ×2-only
run, and a number-pad run is genuinely slower than a multiple-choice one.

The results screen shows the top 5 runs for that config, sorted by score
descending then date ascending, with the just-finished run highlighted in sage.

**Banner**, in order of precedence:
- No previous run and score is zero → "Your first run — every one counts".
- No previous run and score above zero → "New personal best".
- Score strictly beats the previous best → "New personal best — beat N".
- Otherwise → "Your best is N".

Equalling a previous best is not a new best.

*Divergence from prototype: it renders "Your best is -1" on a first run scoring
zero, because the sentinel for "no previous best" leaks into the copy.*

---

## 7. Mastery

Per fact, from `FactStat`:

| Level | Rule | Colour |
|---|---|---|
| Mastered | `timedCorrectCount >= 3 && averageMillis < 3000` | Sage |
| Getting there | `attempts > 0`, bar not met | Butter |
| Not yet | `attempts == 0` | Neutral tile |

**`timedCorrectCount`, not `correctCount`.** The mastery bar counts only
correct answers that carried a trustworthy timing — the `timedCorrectCount`
`FactStat` exposes as `FactHistory.correctCount`. A plain `correctCount >= 3`
would be a false-mastery hole: three untimed correct answers (Countdown retries
after a wrong first attempt, recorded with `millis: nil` per section 4) leave
`averageMillis` at 0, which trivially satisfies `< 3000`, so a fact the child
has only ever fumbled through would read as "Mastered". Do not "simplify"
`FactStat.history` back to `correctCount`; `FactStatTests.untimedFirstCorrectStaysZero`
guards against exactly that.

The prototype's hash-based demo pattern — which fabricates a plausible-looking
grid when there is no data — is **removed entirely**. An empty grid is all "Not
yet". Showing a child invented progress would be dishonest.

---

## 8. Screens

Six screens. `NavigationStack` over a `Route` enum. Finishing a game replaces
the path with `[.results]`, so Back from Results goes home rather than
returning into a dead game.

### Home
Brand mark (tile triad — sage, butter, sky — beside the "Tables" wordmark in
Zilla Slab) with a settings gear opposite. Heading "What do you want to
practise?", supporting line, then two mode cards: **Countdown** on sky-tint
with a large "60" numeral, **Revision** on sage-tint with a 2×2 tile motif. A
"Progress · Your tables →" row sits at the bottom.

### Setup
Back button and mode title. Three accordion cards, one open at a time,
defaulting to Tables:

1. **Tables** — 4×3 grid of 1–12, multi-select, with Select all / Clear all.
   Nothing is preselected — the child chooses which tables to practise, and the
   Start button stays disabled until at least one is picked. The summary reads
   "None chosen" until then, otherwise "×3 ×6 ×7 ×8" or "All tables".
2. **Answer mode** — Multiple choice / Number pad radio rows, plus a disabled
   Voice row with a lilac "Soon" chip.
3. **Time limit** (Countdown: 30/60/90/120s) or **Length** (Revision:
   10/20/30/40/50/60/Endless) as pill chips.

Primary CTA "Start countdown" / "Start revision", disabled while no table is
selected.

### Game
Back button, mode eyebrow, and either the countdown timer pill or a Revision
progress pill (`12/20`, or a bare count when Endless).

The problem is the hero, set large in Zilla Slab; on a correct answer the
answer reveals inline beside it. Below it, either the multiple choice grid or
the number pad with its own value display. A reserved strip between them holds
the feedback pill or, while reviewing a wrong Revision answer, the "Try again"
button — so nothing shifts when it appears.

There is no bottom button; the back button in the header leaves the game.

**Number pad:** keys 1–9, ⌫, 0, ↵ in a 3×4 grid. Entry capped at 3 digits.
Submit is enabled only with a value entered.

### Results
Config eyebrow ("Countdown · 60 sec · ×3 ×6 ×7 ×8"), the score at display size,
its unit, the comparison banner, then "Your best runs" — up to 5 rows of rank,
relative date ("Just now", "Earlier today", "Yesterday", "N days ago") and
score. "Play again" restarts the same configuration; "Back home" returns to
Home.

### Progress
"Your tables" with a legend and a 13×13 grid — a header row and column of
multiplicands, then 144 cells coloured by mastery level.

### Settings (sheet)
Three controls only:
- **Sound** — on/off
- **Haptics** — on/off
- **Multiple choice options** — 4 or 6 (default 6)

Backed by `UserDefaults` via an `@Observable AppSettings`.

*Divergence from prototype: it exposes `showFeedback` and `lowTimeWarning` as
authoring props. Both become always-on constants; neither is user-facing.*

---

## 9. Design system

Four token files mirroring the CSS one-for-one, so the design project remains
the source of truth.

### Palette (`colors.css`)

```
paper       #FBFAF7    ink         #2B2A28
canvas      #F2EFE8    inkSoft     #6B6862
tileNeutral #EFEBE3    inkMuted    #8A867E
line        #DDD8CE    border      #E4E0D8    divider #F0EDE6

sage   #B7CDAE  tint #E8EFE2  text #33472C    correct / mastered
butter #F0D999  tint #FAF1D6  text #665012    getting there
blush  #E9AFAB  tint #F7E3E1  text #6E2E2A    incorrect
sky    #A9C7E0  tint #E4EEF6  text #274963    accent / selection
lilac  #C7BEE0  tint #EEEAF6  text #453963    secondary / voice
clay   #B24A3F                                editorial marker
```

### Typography

**Zilla Slab SemiBold** — numbers, problems, headings.
**Libre Franklin Regular / SemiBold** — all interface text.

Both are SIL Open Font License and free to ship commercially. Three **static**
TTFs are bundled (~555KB total) rather than the variable files, because
SwiftUI's `.weight()` does not reliably reach variable-font weight axes.

Sources, verified: Zilla Slab SemiBold from `google/fonts`; Libre Franklin
Regular and SemiBold from the upstream `impallari/Libre-Franklin` repository.
The Libre Franklin statics that Google's CDN generates are **not** usable —
they carry the PostScript name `LibreFranklinThin-Regular` and cover only 228
glyphs against upstream's 919.

Every size goes through `.custom(_, size:relativeTo:)` so Dynamic Type still
scales the app.

**Glyph coverage.** Three symbols the prototype sets as text are absent from
the bundled fonts and would silently fall back to the system face:

| Symbol | Used for | Replacement |
|---|---|---|
| `→` | "Your tables →" on Home | SF Symbol `arrow.right` |
| `⌫` | Number pad delete key | SF Symbol `delete.left` |
| `↵` | Number pad submit key | SF Symbol `checkmark` |

SF Symbols are the better answer on iOS regardless — they match the system's
2pt-stroke rounded icon language, scale with Dynamic Type, and are legible to
VoiceOver. `×` (U+00D7), `·` and `—` are all present in both families and stay
as text.

Caps labels ("eyebrows") are 11–12pt Libre Franklin SemiBold, uppercase, with
`0.16em` tracking. Everything else is sentence case. The multiplication sign is
always `×` (U+00D7), never a lowercase "x".

### Metrics

4pt spacing rhythm (4, 8, 12, 16, 20, 26, 32, 40, 56, 72). Radii: swatch 6,
key 8, tile 10, card 14, pill 999. Tile stroke 2pt, card border 1pt. Minimum
touch target 44pt.

Nearly flat: surfaces read through warm tints and hairline borders. The only
shadow is a soft lift reserved for sheets.

### Motion

80ms press · 180ms colour fade · 300ms tile pop (scale 1 → 1.12 → 1) · 400ms
reveal. Easing `cubic-bezier(0.22, 1, 0.36, 1)`.

`Motion` reads `\.accessibilityReduceMotion` and returns no animation when it
is on, so honouring Reduce Motion is one decision made once rather than a
choice repeated in every view. Nothing loops or idles.

---

## 10. Feedback services

**Haptics** — `.impact(.light)` on correct, `.notification(.warning)` on wrong.
Gated on the Haptics setting.

**Sound** — no audio assets exist and none need to be licensed. `SoundPlayer`
synthesises two short enveloped sine tones through `AVAudioEngine`: a soft high
tone for correct, a lower one for wrong. Fast attack, gentle decay, under
200ms. Audio session category `.ambient`, so the hardware silent switch and any
music already playing both take precedence. Gated on the Sound setting.

---

## 11. Testing

### Unit (Swift Testing), with seeded RNG

- **DistractorGenerator** — returns exactly the requested count; always
  contains the answer; all values unique and positive; behaves when the answer
  is small (1 × 1) and large (12 × 12).
- **QuestionPicker** — unseen facts exhausted before any repeat; slow facts
  favoured over fast across many seeded draws; never repeats consecutively;
  single-fact pool does not deadlock.
- **Mastery** — the 3-correct / sub-3000ms boundary from both sides; unseen
  facts are "Not yet".
- **ScoreBoard** — top-5 ordering; score-tie broken by earlier date; new-best
  on a first non-zero run; new-best on beating a previous best; not a new best
  on equalling it.
- **FactStat** — EMA maths, first-correct initialisation, wrong answers leave
  the average untouched.
- **GameSession** — Countdown retries do not double-score; Countdown records a
  fact's time only on first correct; Revision reveals then advances; fixed
  length terminates at exactly N; Endless terminates only on Finish; ending
  with zero answered records no run; backgrounding pauses and resumes the
  clock.

### UI (XCTest)

One smoke path: launch → Countdown → Start → answer a question → Results.

---

## 12. Out of scope for v1

- Voice answer mode (designed, shown as "Soon")
- Dark mode
- Landscape
- Division, addition, or any operation other than multiplication
- Accounts, sync, sharing, streaks, notifications
