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

`.github/workflows/release.yml` (#83) runs when a `vX.Y.Z` tag is pushed. A tag ruleset lets
only the maintainer create `v*` tags.

### Cut a release

1. On a branch, `scripts/bump-version X.Y.Z`, commit (`chore(release): bump version to X.Y.Z`),
   open a PR, and merge it once CI is green.
2. Tag the merge commit on `main` with a message; its first line is a title, and the rest
   (Markdown) is the release's summary, shown above GitHub's generated notes and in Sparkle's
   update alert:

   ```sh
   git switch main && git pull
   git tag -s vX.Y.Z -m "Peep X.Y.Z" -m "A short summary of what changed."   # or -a
   git push origin vX.Y.Z
   ```

3. Actions > Release: approve the `release` deployment for `build` (Review deployments). When
   the release is published (after notarization, usually several minutes), approve it again for
   `cask`. GitHub's review is for the jobs waiting at that moment, and `cask` only queues after
   `publish`, so expect a second prompt (to be confirmed on the first run). `deployment: false`
   wouldn't avoid it: required reviewers still apply. The second approval is also a last look
   at the published release before Homebrew users get it.
4. Check: the [release](https://github.com/itspriddle/peep/releases/latest),
   `curl -s https://peep.now/appcast.xml` (the new item, ending in a `sparkle-signatures` comment), and
   `brew upgrade --cask itspriddle/brews/peep` (or install).

A tag that isn't `vX.Y.Z` (`v0.2.0-beta.1`, `v1.0`) fails the first job; pre-releases aren't
supported (a beta would be a `<sparkle:channel>` item, VISION). Delete such a tag with
`git push origin :refs/tags/TAG`.

### What each job does

| Job | Runner, environment | Does |
| --- | --- | --- |
| `check` | ubuntu, no secrets | Tag is `vX.Y.Z`; `scripts/check-version TAG`; the commit is on `main`; no published release has the tag; the tag is newer than the latest release; downloads that release's `appcast.xml`; takes the tag message's body as the summary (signature stripped). |
| `build` | macos-26, `release` | Throwaway keychain (random password, the `.p12` imported from a mode 600 temporary file that is deleted at once, `set-key-partition-list`; deleted in an `always()` step); `scripts/package-release` (never `--skip-notarize`); `scripts/release-appcast` on the stapled DMG; uploads the DMG, `.sha256`, and `appcast.xml` (artifact `release`) and the notary log (`notary`). |
| `publish` | ubuntu, `contents: write` | Checks the DMG against its `.sha256`; creates the release as a draft (`--verify-tag`, title "Peep X.Y.Z", the summary plus `--generate-notes`) with the three files, then publishes it and marks it latest. |
| `site` | `deploy-site.yml` (`site` environment) | Deploys `main`'s `Site/`; its build copies the now latest release's `appcast.xml` into `dist/`. |
| `cask` | ubuntu, `release` | `scripts/render-cask X.Y.Z SHA256` into `Casks/peep.rb` of `itspriddle/homebrew-brews` (`master`), commits "Updated peep to vX.Y.Z" as `github-actions[bot]`, pushes with `HOMEBREW_TAP_TOKEN` (checkout keeps no credentials). |

Secrets reach only the step that uses them, as environment variables. Sparkle's key goes to
its tools on standard input (`--ed-key-file -`), and `scripts/release-appcast` unsets it from
its own environment first. Third-party actions are pinned by commit SHA.

### The appcast

`https://peep.now/appcast.xml` is the signed file attached to the latest published release.
The site build (`Site/scripts/fetch-release.ts`, the last step of `vp run build`) downloads it
from the GitHub API without a token. It fails the build if a release exists without a signed
`appcast.xml` (no `sparkle-signatures` comment), and ships none (a real 404,
`not_found_handling: none`) before the first release. A manual site deploy therefore
republishes the same signed feed; the site never holds the Sparkle key.

The same step writes `dist/_redirects` with one rule, `/download` → the latest release's
`Peep-X.Y.Z.dmg` (302), which the page's Download button uses, so every release's site deploy
moves the link. It fails the build if the release has no DMG for its tag.

`scripts/release-appcast` builds each release's feed from the previous one: it verifies the
previous feed's signature with the same key, refuses a version that's already in it, runs
`generate_appcast` (every earlier item kept, no deltas, minimum macOS and build number from the
app, enclosure `https://github.com/itspriddle/peep/releases/download/vX.Y.Z/Peep-X.Y.Z.dmg`,
full release notes link to the release page, the tag summary embedded as Markdown), fails if
the key isn't the app's `SUPublicEDKey` (`generate_appcast` only warns and leaves the item
unsigned), then verifies the feed's signature and the new item's signature over the DMG.

### Recover from a failed run

Never re-sign or replace a published DMG: users and the appcast already have its hash and
signature. Fix forward with a new patch version instead.

- **`check` failed:** nothing happened. Fix the cause (bump, merge), delete the tag
  (`git push origin :refs/tags/vX.Y.Z`), and tag again.
- **`build` failed** (signing, notarization, the appcast): nothing was published. Re-run the
  job if the cause was transient (the notary service), else fix it, delete and re-push the tag.
  A rejection prints the notary log; the `notary` artifact has it too.
- **`publish` failed:** re-run failed jobs (same run, same artifacts). An existing draft gets
  its assets replaced (`--clobber`); a release this run already published is accepted only if
  its DMG has the same SHA-256. Delete a stray draft by hand if you abandon the run.
- **`site` failed:** re-run it, or run Actions > Deploy site on `main`; either serves the latest
  release's appcast.
- **`cask` failed:** re-run it. An unchanged `Casks/peep.rb` is a no-op; a push race with
  another tap commit just needs another re-run.
- **A whole new run for a tag that's already published** fails in `check`, before any approval.

Recommended: Settings > General > Releases > enable immutable releases, so a published
release's assets and tag can't change at all (the workflow uploads everything while the release
is a draft, so it works with it on).

### Rotate secrets

All are `release` environment secrets (Settings > Environments > release), except
`APPLE_TEAM_ID` (an environment variable) and the Cloudflare pair (`site` environment).

| Secret | Rotate |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | New Developer ID Application certificate (developer.apple.com, or Xcode > Settings > Accounts); export it with its key from Keychain Access as `.p12` with a new password; `base64 -i cert.p12 \| pbcopy` into `DEVELOPER_ID_P12_BASE64`, the password into `DEVELOPER_ID_P12_PASSWORD`; delete the `.p12`. Only one valid identity per team, or set `PEEP_SIGNING_IDENTITY` in the workflow. Sparkle requires the same Developer ID across an update unless the EdDSA key stays the same: never change both in one release. |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect > Users and Access > Integrations > Team Keys: new key (Developer), paste the `.p8` contents, key id, and issuer id; revoke the old key. |
| `SPARKLE_ED_PRIVATE_KEY` | Only if it leaked, and as its own planned change: installed copies verify the feed and the DMG with the key they shipped with (`SURequireSignedFeed`), so a switch strands copies that haven't taken a release carrying the new public key. Sparkle's "Rotating keys" documentation and VISION (Updates) have the rules; never change the key and the Developer ID in the same release. |
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT, repository `itspriddle/homebrew-brews` only, Contents read and write; set an expiry and replace it before then. |
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | `site` environment; a Workers edit token scoped to the account. |

`deploy-site.yml` declares the Cloudflare secrets `required` and the release workflow passes
them by name: a reusable workflow's job reads its own environment's secrets, but only those its
caller passes ("The caller workflow must still pass the secret... You can pass a secret by name
even if it only exists in the environment", GitHub Docs, *Reuse workflows*). Unpassed, they'd be
empty strings without an error.

### Gotchas

- The appcast can be checked locally with a throwaway key: a base64 32-byte seed is a Sparkle
  private key, and the app's `SUPublicEDKey` must be its public key (re-sign a test copy ad hoc;
  `generate_appcast` refuses an app whose signature is broken).
- `generate_appcast` caches extracted archives in `~/Library/Caches/Sparkle_generate_appcast`.
- The `release` environment allows only `v*` tags, so the workflow can't be run from a branch;
  test changes to it on a fork with its own environment and secrets.
