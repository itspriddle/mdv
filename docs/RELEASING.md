# Releasing Peep

A release is a Developer ID signed, notarized, stapled DMG (`Peep-X.Y.Z.dmg`) with the app and
an `/Applications` link. `scripts/package-release` (`make release`) makes it, the same way on the
maintainer's Mac and in CI.

## Before the first release

- **Sparkle key pair:** `Config/Shared.xcconfig` holds the public `SPARKLE_PUBLIC_ED_KEY`
  (#81's handoff has the `generate_keys` steps); the private key is the `release`
  environment's `SPARKLE_ED_PRIVATE_KEY`. If the public key isn't a base64 32-byte key,
  Release builds fail and `scripts/package-release` stops before building (exit 78).
- **Developer ID Application certificate** for the team, in the login keychain (local) or the
  `release` environment's `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` (CI).
- **Notary credentials:** an App Store Connect API key (Users and Access > Integrations > Team
  Keys, role Developer). CI reads it from `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, and
  `NOTARY_ISSUER_ID`. Locally, either export the same three variables or store a profile once:

  ```sh
  xcrun notarytool store-credentials peep-notary \
    --key ~/path/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer UUID>
  ```

## Packaging locally

```sh
scripts/bump-version 0.1.1                        # if not done yet; commit it
PEEP_NOTARY_PROFILE=peep-notary make release      # or export NOTARY_KEY_P8/_ID/ISSUER_ID
make release NOTARIZE=0                           # dry run: signed, not notarized
```

What the script does, in order (it stops at the first failure):

1. Checks the configuration before building: the version (`scripts/check-version`), the team
   (`DEVELOPMENT_TEAM`, else `Config/Local.xcconfig`), exactly one valid
   `Developer ID Application: … (TEAM)` identity, a real Sparkle public key, and notary
   credentials.
2. Empties `build/release`, runs `make cli-docs` (the Release build bundles the man page) and
   `xcodegen generate`, and archives the Release build (`build/release/Peep.xcarchive`, kept for
   its dSYMs) signed ad hoc.
3. Signs inside out with the Developer ID identity, `--options runtime --timestamp`, and never
   `--deep`: Sparkle's `Installer.xpc`, `Downloader.xpc` (keeping its entitlements),
   `Autoupdate`, `Updater.app`, `Sparkle.framework`, then `Contents/Helpers/peep` (identifier
   `now.peep.Peep.cli`, no entitlements) and `Peep.app` (`App/Peep.entitlements`).
4. Verifies: `codesign --verify --deep --strict`, then every Mach-O in the bundle must have our
   team's Developer ID, the hardened runtime, a secure timestamp, and neither `get-task-allow`
   nor `com.apple.application-identifier` (which Xcode's ad hoc signature gives the helper and
   which would need a provisioning profile).
5. Makes the DMG (`hdiutil`, UDZO, HFS+, volume "Peep") and signs it.
6. Notarizes it (`xcrun notarytool submit --wait`), saving the result and the notary log in
   `build/release/notary/`; on a rejection it prints the log and fails. Then staples and
   validates the ticket.
7. Mounts the DMG read-only and checks the copy users get: `codesign --verify --deep --strict`,
   `spctl -a -t exec` (app) and `spctl -a -t open --context context:primary-signature` (DMG),
   then runs its `peep`: `--version` must equal `MARKETING_VERSION`, `--html README.md` and
   `echo '# x' | peep --html` must render.
8. Writes `build/release/Peep-X.Y.Z.dmg.sha256` (`shasum -a 256` format).

`--skip-notarize` skips step 6 and the `spctl` checks (Gatekeeper rejects an un-notarized
Developer ID build); never ship that DMG.

### Environment

| Variable | Meaning |
| --- | --- |
| `DEVELOPMENT_TEAM` | Team ID; default `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`. Never committed. |
| `PEEP_SIGNING_KEYCHAIN` | Keychain file holding the identity (CI's throwaway keychain); passed to `codesign --keychain` and `security find-identity`. Unset: the search list. |
| `PEEP_SIGNING_IDENTITY` | SHA-1 of the identity, only needed when the team has more than one valid Developer ID Application certificate (a renewal overlap). |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect API key: the `.p8` file's contents (written to a mode 600 temporary file, deleted on exit), its key id, and the issuer id. |
| `PEEP_NOTARY_PROFILE` | A `notarytool store-credentials` profile, used when `NOTARY_KEY_P8` isn't set. |

Exit status: 0 packaged; 64 usage; 78 configuration (team, identity, Sparkle key, notary
credentials, a missing tool); 1 a failed step.

### Why the script signs, not Xcode

The archive is built ad hoc (`CODE_SIGN_IDENTITY=-`, no injected base entitlements) and the
script signs every Mach-O itself, instead of `xcodebuild -exportArchive` with the `developer-id`
method:

- One signing pass, written down in one place, that the Mach-O check then proves; Sparkle's
  documented manual order is followed exactly.
- `codesign --keychain` takes CI's throwaway keychain directly. The build needs neither the
  identity, a team, nor an Xcode account, and there is no export options plist.
- Re-signing replaces whatever signature Sparkle's binary package came with.

### Gotchas

- Sparkle's binaries live under `Sparkle.framework/Versions/B`. When a Sparkle update changes
  that layout the script fails ("Sparkle's layout changed"), and the signing list needs a look.
- Packaging runs the packaged helper (from the mounted DMG) but never launches the app.
- Only the DMG is stapled. Its ticket covers the app inside (notarization records every
  signature in the submission); an app copied out of the DMG is otherwise checked online by
  Gatekeeper on first launch. Stapling the app too would take a second submission (the app,
  then the DMG made from the stapled app).
- The direct Apple Event path (two copies running, VISION "CLI to app") needs no
  `com.apple.security.automation.apple-events` entitlement: tested with a Developer ID signed,
  hardened runtime build (#82). TCC treats the helper as part of its enclosing app, and that
  path only ever sends to its own copy of the app, so the app is sending events to itself:
  the event arrived, with no consent prompt. Don't add the entitlement; it would only let Peep
  ask to control other apps.
- `xcodebuild -quiet` still prints "error: the following command failed with exit code 0 but
  produced no further output" for compiler warnings; it isn't a failure (the exit status is
  what counts).
- Keychain prompts: locally, the first `codesign` with the login keychain's key may ask to
  allow access ("Always Allow" covers `codesign`). CI's keychain needs
  `security set-key-partition-list` so it never prompts.

## Releasing from CI

Tag-driven; added by #83.
