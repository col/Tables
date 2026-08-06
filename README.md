<p align="center">
  <img src="docs/assets/logo.png" alt="Tables app icon" width="160">
</p>

<h1 align="center">Tables</h1>

<p align="center"><em>Calm times tables practice</em></p>

<p align="center">
  <a href="https://tables.challengr.io">Website</a> ·
  <a href="https://tables.challengr.io/support">Support</a> ·
  <a href="https://tables.challengr.io/privacy">Privacy</a>
</p>

---

Tables is a calm, focused way for children to practise their times tables — no ads, no accounts, and none of the mascots, confetti, or noise that fill most kids' maths apps. Just multiplication, one question at a time.

Built for the whole of primary school, Tables covers every multiplication fact from 1×1 to 12×12 and lets your child work on exactly the tables they need.

### Two ways to practise

- **Countdown** — a gentle race against the clock. How many can they answer correctly in 30, 60, 90, or 120 seconds?
- **Revision** — no timer, no pressure. Questions lean toward the facts your child has been slower to answer, so practice targets the tables that actually need it.

### Answer your way

- **Multiple choice** — tap the right answer from a grid of four or six tiles.
- **Number pad** — a clean, built-in keypad (never the system keyboard), so the screen stays simple and distraction-free.
- **Voice** — say the answer out loud, hands free, with recognition that happens on device.

### See real progress

A visual mastery grid shows which facts your child has locked in and which still need work — built only from real practice, never guessed or padded out.

### Private by design

No login. No account. No sign-up. Everything stays on the device — nothing is uploaded and there is nothing to manage. Open the app and start.

### Designed to be calm

Quiet visuals, warm typography, and optional sound and haptics you can switch off. Tables feels closer to a well-made puzzle app than a noisy game — the kind of thing you are happy to hand over.

For iPhone and iPad.

---

## A personal note

I built Tables for my daughter. She needed to drill her times tables, and every app I tried buried the maths under cartoon characters, streak counters, and pestering for a subscription. I wanted the opposite: something quiet she could pick up for five minutes, and something I actually trusted — no accounts, no tracking, nothing leaving her iPad.

It was also an experiment in agentic development. Practically all of this app was written by AI agents working from specs and plans I reviewed. The design specs and implementation plans that drove the work are still in [`docs/superpowers/`](docs/superpowers/), which makes the history of the app unusually readable — you can see what was intended before you see what was built.

---

## Built with

SwiftUI · SwiftData · Swift Testing · Speech (on-device recognition) · iOS 26 · Fastlane for release automation

```
Tables/
  DesignSystem/   palette, typography, motion, shared components
  Features/       Home, Setup, Game, Results, Progress, Settings
  Game/           game session and scoring
  Model/          facts, question picking, mastery, persistence
  Services/       settings, feedback, speech recognition
TablesTests/      unit tests (Swift Testing)
```

---

## Releasing

Requires a one-time App Store Connect API key setup — see [`fastlane/README-usage.md`](fastlane/README-usage.md) for that and for the known first-release gotcha.

```sh
bundle install                        # once, to install Fastlane

bundle exec fastlane screenshots      # regenerate App Store screenshots
bundle exec fastlane beta             # build + upload to TestFlight
bundle exec fastlane release          # build + upload binary, metadata, screenshots as a draft
```

`release` uploads a **draft** — open App Store Connect and hit **Submit for Review** yourself. Store listing text lives in `fastlane/metadata/en-AU/`.
