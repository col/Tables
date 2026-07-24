# Fastlane App Store Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Tables iOS app a local Fastlane setup that builds and uploads to TestFlight (`beta`), captures App Store screenshots automatically (`screenshots`), and uploads binary + metadata to App Store Connect as a draft (`release`).

**Architecture:** Bundler pins Fastlane. Auth uses an App Store Connect API key loaded from gitignored files. Signing stays Xcode-Automatic (`gym -allowProvisioningUpdates`), no `match`. Screenshots come from a new `ScreenshotUITests` target class that reuses the app's existing accessibility identifiers and Fastlane's `SnapshotHelper`. `deliver` uploads but never auto-submits.

**Tech Stack:** Ruby 3.3 / Bundler 2.5, Fastlane (gym/pilot/snapshot/deliver), Xcode 26.6, XCUITest.

## Global Constraints

- Bundle identifier: `com.challengr.Tables` (verbatim).
- Team ID: `79242RQ384` (verbatim).
- Scheme: `Tables` (shared; already includes `TablesUITests`).
- Signing: Xcode **Automatic** only — never introduce `match` or manual profiles.
- Secrets (`*.p8`, Key ID, Issuer ID) must **never** be committed. They live in `fastlane/AuthKey_*.p8` and `fastlane/.env`, both gitignored.
- App is **universal** (`TARGETED_DEVICE_FAMILY = "1,2"`) — screenshots cover iPhone + iPad.
- Release lane uses `submit_for_review: false` — always upload-only.
- Locale: `en-US` only.
- Version comes from build settings `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`; Info.plist has no literal version keys. Set build number by passing `CURRENT_PROJECT_VERSION` to `gym` via `xcargs` — do **not** edit `project.pbxproj`.
- Screenshot UI test must pass `-uiTesting` (caps the game countdown; disables persistence) in addition to snapshot's own launch args.
- The existing `GameFlowUITests` must keep passing — screenshot work is additive.

---

## File Structure

- `Gemfile` — pins fastlane, run via `bundle exec`.
- `fastlane/Appfile` — bundle id, team, API-key-based auth reference.
- `fastlane/Fastfile` — `screenshots`, `beta`, `release` lanes + `asc_key` helper.
- `fastlane/Snapfile` — device + language matrix for snapshot.
- `fastlane/Deliverfile` — deliver upload options.
- `fastlane/.env.example` — documents the two IDs (committed); `fastlane/.env` holds real values (gitignored).
- `fastlane/metadata/en-US/*.txt` + `fastlane/metadata/*.txt` — scaffolded App Store metadata the user edits.
- `TablesUITests/SnapshotHelper.swift` — Fastlane's official helper (vendored).
- `TablesUITests/ScreenshotUITests.swift` — new: drives screens, calls `snapshot()`.
- `scripts/add_screenshot_files.rb` — one-off script that adds the two Swift files to the `TablesUITests` target via the `xcodeproj` gem.
- Root `.gitignore` — Fastlane + build artefacts + secrets.

---

## Task 1: Bundler + Fastlane bootstrap

**Files:**
- Create: `Gemfile`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `bundle exec fastlane` runnable in the repo root.

- [ ] **Step 1: Create `Gemfile`**

```ruby
source "https://rubygems.org"

gem "fastlane"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: resolves and writes `Gemfile.lock`; `fastlane` and its dependency `xcodeproj` are installed.

- [ ] **Step 3: Append Fastlane + build artefacts to root `.gitignore`**

Add these lines to `.gitignore` (keep existing lines):

```gitignore
# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/screenshots/screenshots.html
fastlane/test_output/
fastlane/.env
fastlane/AuthKey_*.p8
fastlane/*.p8

# Build artefacts
build/
*.ipa
*.app.dSYM.zip
```

- [ ] **Step 4: Verify Fastlane runs**

Run: `bundle exec fastlane --version`
Expected: prints a `fastlane 2.x.x` version line, no error.

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock .gitignore
git commit -m "Add Bundler-pinned Fastlane and ignore build artefacts"
```

---

## Task 2: Appfile, API-key auth helper, and lane skeleton

**Files:**
- Create: `fastlane/Appfile`
- Create: `fastlane/Fastfile`
- Create: `fastlane/.env.example`

**Interfaces:**
- Produces: an `asc_key` helper method returning the API key hash used by every lane; `bundle exec fastlane lanes` lists `screenshots`, `beta`, `release`.
- Consumes (from the user, at runtime): `fastlane/AuthKey_<KEYID>.p8`, and `fastlane/.env` defining `ASC_KEY_ID` and `ASC_ISSUER_ID`.

- [ ] **Step 1: Create `fastlane/Appfile`**

```ruby
app_identifier("com.challengr.Tables")
team_id("79242RQ384")
```

- [ ] **Step 2: Create `fastlane/.env.example`**

```bash
# Copy to fastlane/.env and fill in with your App Store Connect API key details.
# App Store Connect > Users and Access > Integrations > App Store Connect API.
# The .p8 file itself goes in fastlane/AuthKey_<KEYID>.p8 (gitignored).
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

- [ ] **Step 3: Create `fastlane/Fastfile` with the auth helper and lane stubs**

```ruby
default_platform(:ios)

# Loads the App Store Connect API key from gitignored files. The .p8 is
# located by ASC_KEY_ID; the two IDs come from fastlane/.env.
def asc_key
  key_id = ENV.fetch("ASC_KEY_ID") { UI.user_error!("Set ASC_KEY_ID in fastlane/.env (see .env.example)") }
  issuer_id = ENV.fetch("ASC_ISSUER_ID") { UI.user_error!("Set ASC_ISSUER_ID in fastlane/.env (see .env.example)") }
  key_path = File.expand_path("AuthKey_#{key_id}.p8", __dir__)
  UI.user_error!("Missing #{key_path} — download it from App Store Connect") unless File.exist?(key_path)
  app_store_connect_api_key(
    key_id: key_id,
    issuer_id: issuer_id,
    key_filepath: key_path,
    in_house: false
  )
end

platform :ios do
  desc "Capture App Store screenshots on the simulator matrix"
  lane :screenshots do
    UI.message("screenshots lane wired in Task 3")
  end

  desc "Build and upload a new build to TestFlight"
  lane :beta do
    UI.message("beta lane wired in Task 4")
  end

  desc "Build and upload binary + metadata + screenshots to App Store Connect (draft, not submitted)"
  lane :release do
    UI.message("release lane wired in Task 5")
  end
end
```

- [ ] **Step 4: Verify lanes list**

Run: `bundle exec fastlane lanes`
Expected: lists `ios screenshots`, `ios beta`, `ios release` with their descriptions, no error. (`.env` need not exist yet — the helper only runs when a lane calls it.)

- [ ] **Step 5: Commit**

```bash
git add fastlane/Appfile fastlane/Fastfile fastlane/.env.example
git commit -m "Add Fastlane Appfile, ASC API-key helper, and lane skeleton"
```

---

## Task 3: Screenshot UI test + snapshot lane

**Files:**
- Create: `TablesUITests/SnapshotHelper.swift`
- Create: `TablesUITests/ScreenshotUITests.swift`
- Create: `scripts/add_screenshot_files.rb`
- Create: `fastlane/Snapfile`
- Modify: `fastlane/Fastfile` (replace the `screenshots` lane body)
- Modify: `Tables.xcodeproj/project.pbxproj` (via the script, not by hand)

**Interfaces:**
- Consumes: `asc_key` is NOT needed here (simulator only).
- Produces: `fastlane screenshots` writes PNGs to `fastlane/screenshots/en-US/`.
- Reuses existing identifiers: `home.countdown`, `home.progress`, `setup.table.3`, `setup.start`, `game.problem`, `game.option.<n>`, `results.score`.

- [ ] **Step 1: Vendor Fastlane's SnapshotHelper**

Run: `bundle exec fastlane snapshot update --path TablesUITests`
Expected: writes `TablesUITests/SnapshotHelper.swift`.

If that command is unavailable, download it instead:
Run: `curl -sSL https://raw.githubusercontent.com/fastlane/fastlane/master/snapshot/lib/assets/SnapshotHelper.swift -o TablesUITests/SnapshotHelper.swift`
Expected: file exists and defines `func setupSnapshot(_ app: XCUIApplication...)` and `func snapshot(_ name: String...)`.

- [ ] **Step 2: Create `TablesUITests/ScreenshotUITests.swift`**

```swift
import XCTest

final class ScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        // -uiTesting caps the countdown and disables persistence (see SetupModel/GameView).
        app.launchArguments += ["-uiTesting"]
        app.launch()
    }

    func testCaptureScreens() throws {
        // 01 Home
        let countdown = app.buttons["home.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 15))
        snapshot("01Home")

        // 02 Setup
        countdown.tap()
        let table = app.buttons["setup.table.3"]
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        table.tap()
        snapshot("02Setup")

        // 03 Game
        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let problem = app.staticTexts["game.problem"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        snapshot("03Game")

        // 04 Results — answer correctly, then the capped clock carries us to Results.
        let factors = problem.label
            .components(separatedBy: "\u{00D7}")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if factors.count == 2 {
            let option = app.buttons["game.option.\(factors[0] * factors[1])"]
            if option.waitForExistence(timeout: 5) { option.tap() }
        }
        let score = app.staticTexts["results.score"]
        XCTAssertTrue(score.waitForExistence(timeout: 20))
        snapshot("04Results")
    }

    func testCaptureProgress() throws {
        // 05 Progress
        let progress = app.buttons["home.progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 15))
        progress.tap()
        XCTAssertTrue(app.staticTexts["Your tables"].waitForExistence(timeout: 10))
        snapshot("05Progress")
    }
}
```

- [ ] **Step 3: Create `scripts/add_screenshot_files.rb`**

```ruby
# Adds SnapshotHelper.swift and ScreenshotUITests.swift to the TablesUITests
# target. Idempotent: skips files already present. Run: bundle exec ruby scripts/add_screenshot_files.rb
require "xcodeproj"

project_path = File.expand_path("../Tables.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == "TablesUITests" }
raise "TablesUITests target not found" unless target

group = project.main_group.find_subpath("TablesUITests", true)
existing = target.source_build_phase.files_references.map(&:path).compact

["SnapshotHelper.swift", "ScreenshotUITests.swift"].each do |filename|
  if existing.include?(filename)
    puts "already added: #{filename}"
    next
  end
  file_ref = group.new_reference(filename)
  target.add_file_references([file_ref])
  puts "added: #{filename}"
end

project.save
puts "saved #{project_path}"
```

- [ ] **Step 4: Run the script to register the files**

Run: `bundle exec ruby scripts/add_screenshot_files.rb`
Expected: prints `added: SnapshotHelper.swift`, `added: ScreenshotUITests.swift`, `saved …`.

- [ ] **Step 5: Verify the UITests target compiles with the new files**

Run: `xcodebuild build-for-testing -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -quiet`
Expected: `** TEST BUILD SUCCEEDED **` (no compile errors referencing `snapshot`/`setupSnapshot`). If the exact simulator name is missing, list available names with `xcrun simctl list devicetypes | grep iPhone` and substitute one.

- [ ] **Step 6: Create `fastlane/Snapfile`**

```ruby
# Only run the screenshot class, not the full UITest suite.
only_testing(["TablesUITests/ScreenshotUITests"])

devices([
  "iPhone 16 Pro Max",   # 6.9"
  "iPhone 16 Plus",      # 6.7"
  "iPad Pro 13-inch (M4)"
])

languages(["en-US"])

scheme("Tables")
output_directory("./fastlane/screenshots")
clear_previous_screenshots(true)
concurrent_simulators(true)
stop_after_first_error(true)
```

> If any device name is not installed, replace it with a name from `xcrun simctl list devicetypes`.

- [ ] **Step 7: Replace the `screenshots` lane body in `fastlane/Fastfile`**

Replace the `screenshots` lane from Task 2 with:

```ruby
  desc "Capture App Store screenshots on the simulator matrix"
  lane :screenshots do
    capture_screenshots
  end
```

- [ ] **Step 8: Verify screenshots are produced**

Run: `bundle exec fastlane screenshots`
Expected: completes and writes PNGs under `fastlane/screenshots/en-US/` named `01Home`, `02Setup`, `03Game`, `04Results`, `05Progress` for each device. A `screenshots.html` summary is generated.

- [ ] **Step 9: Verify existing UI tests still pass**

Run: `xcodebuild test -scheme Tables -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:TablesUITests/GameFlowUITests -quiet`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add TablesUITests/SnapshotHelper.swift TablesUITests/ScreenshotUITests.swift scripts/add_screenshot_files.rb fastlane/Snapfile fastlane/Fastfile Tables.xcodeproj/project.pbxproj
git commit -m "Add automated App Store screenshots via snapshot"
```

---

## Task 4: `beta` lane — build and upload to TestFlight

**Files:**
- Modify: `fastlane/Fastfile` (replace the `beta` lane body)

**Interfaces:**
- Consumes: `asc_key` (Task 2); scheme `Tables`.
- Produces: `fastlane beta` archives with an auto-incremented build number and uploads to TestFlight.

- [ ] **Step 1: Replace the `beta` lane body in `fastlane/Fastfile`**

```ruby
  desc "Build and upload a new build to TestFlight"
  lane :beta do
    key = asc_key

    # Next build number = highest on TestFlight + 1 (start at 1 if none yet).
    latest = latest_testflight_build_number(
      api_key: key,
      app_identifier: "com.challengr.Tables",
      initial_build_number: 0
    )
    next_build = latest + 1
    UI.message("Building TestFlight build number #{next_build}")

    build_app(
      scheme: "Tables",
      export_method: "app-store",
      xcargs: "CURRENT_PROJECT_VERSION=#{next_build} -allowProvisioningUpdates",
      output_directory: "build",
      clean: true
    )

    upload_to_testflight(
      api_key: key,
      skip_waiting_for_build_processing: true
    )
  end
```

- [ ] **Step 2: Verify the lane parses**

Run: `bundle exec fastlane lanes`
Expected: `ios beta` still listed, no Ruby syntax error.

- [ ] **Step 3: (Requires user's API key) Verify an end-to-end upload**

Prerequisite: user has placed `fastlane/AuthKey_<KEYID>.p8` and filled `fastlane/.env`.
Run: `bundle exec fastlane beta`
Expected: archives, signs via Automatic signing, uploads; the build appears in App Store Connect → TestFlight within a few minutes. Mark this step done only after the user confirms, or note it as user-verified.

- [ ] **Step 4: Commit**

```bash
git add fastlane/Fastfile
git commit -m "Add beta lane: build and upload to TestFlight"
```

---

## Task 5: `release` lane + Deliverfile + metadata scaffold

**Files:**
- Modify: `fastlane/Fastfile` (replace the `release` lane body)
- Create: `fastlane/Deliverfile`
- Create: `fastlane/metadata/en-US/name.txt`
- Create: `fastlane/metadata/en-US/subtitle.txt`
- Create: `fastlane/metadata/en-US/description.txt`
- Create: `fastlane/metadata/en-US/keywords.txt`
- Create: `fastlane/metadata/en-US/promotional_text.txt`
- Create: `fastlane/metadata/en-US/release_notes.txt`
- Create: `fastlane/metadata/en-US/support_url.txt`
- Create: `fastlane/metadata/en-US/marketing_url.txt`
- Create: `fastlane/metadata/en-US/privacy_url.txt`

**Interfaces:**
- Consumes: `asc_key` (Task 2); `fastlane/screenshots/` (Task 3).
- Produces: `fastlane release` uploads binary + metadata + screenshots as a draft (never submits).

- [ ] **Step 1: Create the metadata files (placeholder text the user edits)**

`fastlane/metadata/en-US/name.txt`:
```
Tables
```
`fastlane/metadata/en-US/subtitle.txt`:
```
Master your times tables
```
`fastlane/metadata/en-US/description.txt`:
```
TODO: Write the App Store description for Tables before releasing.
```
`fastlane/metadata/en-US/keywords.txt`:
```
times tables,multiplication,math,maths,practice,kids
```
`fastlane/metadata/en-US/promotional_text.txt`:
```
Practice your times tables with quick, focused challenges.
```
`fastlane/metadata/en-US/release_notes.txt`:
```
Initial release.
```
`fastlane/metadata/en-US/support_url.txt`:
```
https://example.com/tables/support
```
`fastlane/metadata/en-US/marketing_url.txt`:
```
https://example.com/tables
```
`fastlane/metadata/en-US/privacy_url.txt`:
```
https://example.com/tables/privacy
```

> The three URL files and `description.txt` are the ones the user MUST replace with real values. Apple rejects placeholder/`example.com` URLs and requires a working privacy policy URL.

- [ ] **Step 2: Create `fastlane/Deliverfile`**

```ruby
# Upload-only: never auto-submit. The user clicks Submit in App Store Connect.
submit_for_review(false)
automatic_release(false)
force(true)                 # skip the HTML preview confirmation prompt
precheck_include_in_app_purchases(false)
screenshots_path("./fastlane/screenshots")
metadata_path("./fastlane/metadata")
```

- [ ] **Step 3: Replace the `release` lane body in `fastlane/Fastfile`**

```ruby
  desc "Build and upload binary + metadata + screenshots to App Store Connect (draft, not submitted)"
  lane :release do
    key = asc_key

    build_app(
      scheme: "Tables",
      export_method: "app-store",
      xcargs: "-allowProvisioningUpdates",
      output_directory: "build",
      clean: true
    )

    upload_to_app_store(
      api_key: key,
      submit_for_review: false,
      automatic_release: false,
      force: true,
      precheck_include_in_app_purchases: false,
      metadata_path: "./fastlane/metadata",
      screenshots_path: "./fastlane/screenshots"
    )
  end
```

- [ ] **Step 4: Verify the lane parses**

Run: `bundle exec fastlane lanes`
Expected: `ios release` listed, no Ruby error.

- [ ] **Step 5: (Requires user's API key + edited metadata) Verify end-to-end**

Run: `bundle exec fastlane release`
Expected: builds, uploads binary, metadata, and screenshots; the version appears in App Store Connect in a non-submitted (Prepare for Submission) state. Mark done only after user confirms, or note as user-verified.

- [ ] **Step 6: Commit**

```bash
git add fastlane/Fastfile fastlane/Deliverfile fastlane/metadata
git commit -m "Add release lane, Deliverfile, and metadata scaffold"
```

---

## Task 6: Usage documentation

**Files:**
- Create: `fastlane/README-usage.md`

**Interfaces:**
- Consumes: everything above.
- Produces: a short doc so the user knows the one-time setup and daily commands.

- [ ] **Step 1: Create `fastlane/README-usage.md`**

```markdown
# Fastlane usage

## One-time setup
1. Create an App Store Connect API key: App Store Connect > Users and Access >
   Integrations > App Store Connect API > "+". Give it App Manager access.
   Download the `.p8` (you can only download it once).
2. Put the file at `fastlane/AuthKey_<KEYID>.p8`.
3. `cp fastlane/.env.example fastlane/.env` and fill in `ASC_KEY_ID`
   (the key's ID) and `ASC_ISSUER_ID` (shown above the keys list).
4. Edit `fastlane/metadata/en-US/description.txt` and the three `*_url.txt`
   files with real values (no example.com — Apple rejects those).
5. Accept any pending agreements in App Store Connect (free-app agreement).

## Commands
- `bundle exec fastlane screenshots` — regenerate App Store screenshots.
- `bundle exec fastlane beta` — build and upload to TestFlight.
- `bundle exec fastlane release` — build and upload binary + metadata +
  screenshots to App Store Connect as a draft. Then open App Store Connect
  and click **Submit for Review** yourself.

## Notes
- Signing is Xcode Automatic; `gym` passes `-allowProvisioningUpdates`.
- Secrets (`.p8`, `.env`) are gitignored — never commit them.
- To change screenshot devices, edit `fastlane/Snapfile` (names must match
  `xcrun simctl list devicetypes`).
```

- [ ] **Step 2: Commit**

```bash
git add fastlane/README-usage.md
git commit -m "Document Fastlane usage and one-time setup"
```

---

## Self-Review Notes

- **Spec coverage:** signing decision (Global Constraints + Tasks 4/5 `-allowProvisioningUpdates`); API-key auth (Task 2 `asc_key`); `.env`/`.p8` gitignore (Task 1); `screenshots` lane (Task 3); `beta`/pilot (Task 4); `release`/deliver upload-only (Task 5); iPhone+iPad devices (Task 3 Snapfile); en-US only (Snapfile/Deliverfile); build-number auto-increment without pbxproj edits (Task 4 `xcargs`); manual metadata/URL tasks (Task 5 + Task 6 doc). All spec sections mapped.
- **Placeholder scan:** metadata `.txt` files contain deliberate placeholder copy the user must replace; every code/config step contains complete content. No plan-level TBDs.
- **Type consistency:** `asc_key` defined once (Task 2), consumed verbatim in Tasks 4 and 5. Identifier strings (`home.countdown`, `setup.table.3`, `setup.start`, `game.problem`, `game.option.<n>`, `results.score`, `home.progress`) match the existing `GameFlowUITests`. Snapshot names `01Home`…`05Progress` are consistent between the test and the documented output.
