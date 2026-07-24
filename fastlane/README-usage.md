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
6. Make sure the app record for `com.challengr.Tables` already exists in
   App Store Connect. The `beta`/`release` lanes upload to it but do not
   create it — the first `fastlane beta` fails at `latest_testflight_build_number`
   if the app hasn't been registered (register it in the App Store Connect UI,
   or once with `bundle exec fastlane produce`).

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
