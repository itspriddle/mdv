# CLAUDE.md

mdv is a native macOS Markdown viewer with a CLI. Working name; the final name is chosen before M6.
Read `docs/VISION.md` (principles, architecture, security model) and `docs/ROADMAP.md` (milestones,
process) before planning work.

## Commands

```sh
make generate         # regenerate mdv.xcodeproj from project.yml (run after adding/removing files)
make test-core        # swift test (MdvCore), fast, no Xcode project needed
make test             # core + app tests
make build            # app + embedded CLI (signed via Config/Local.xcconfig); SIGN=0 for unsigned
make lint             # swiftlint --strict + swift format lint --strict (CI runs this)
make format           # auto-format; run before committing
swift run mdv --html FILE   # render to stdout without Xcode
```

`.NOTPARALLEL` is set because the user's shell exports `MAKEFLAGS=-j9`; concurrent xcodebuilds
lock the build database.

## Layout

- `Sources/MdvCore`: all rendering logic (parse, transform, HTML, themes, preprocessors). No UI
  imports. New logic goes here so it is testable with `swift test`.
- `App/`: SwiftUI app (module `MdvApp`), kept thin.
- `CLI/`: ArgumentParser `mdv` tool (module `MdvCLI`), built both by SwiftPM and by the Xcode
  `mdv-cli` target, embedded at `mdv.app/Contents/Helpers/mdv`.
- `Tests/MdvCoreTests`, `AppTests/`: Swift Testing (`import Testing`, `@Test`, `#expect`).
- `project.yml`: XcodeGen spec. Never commit `mdv.xcodeproj`; edit `project.yml` instead.
- `Config/Shared.xcconfig`: shared settings. `Config/Local.xcconfig` (gitignored) holds
  `DEVELOPMENT_TEAM`; never commit it or hard-code the team ID.

## Conventions

- Swift 6 language mode, strict concurrency, macOS 15 minimum.
- Lint and format must pass with zero violations; swift-format owns layout, SwiftLint owns smells.
- No force unwraps; prefer failable APIs (e.g. `String(bytes:encoding:)`) and throw on bad input.
- Security defaults from `docs/VISION.md` are requirements: strict CSP, no remote content, JS off
  or bundle-only, sanitize raw HTML, user scripts are opt-in.
- Bundle ID placeholder `com.itspriddle.mdv` lives in `PRODUCT_BUNDLE_IDENTIFIER_BASE` and
  `MdvCommand.appBundleIdentifier`; keep them in sync. Same for `MARKETING_VERSION` and
  `MdvInfo.version`.
- Verify a dependency exists (and its latest version) before adding it.

## Workflow

- GitHub: `itspriddle/mdv` (private until 1.0). Each roadmap milestone is a GitHub milestone with
  issues.
- One branch per issue (Conventional Branch, e.g. `feature/gfm-tables`), Conventional Commits
  (see `.claude/skills`). PRs must pass CI.
- When a milestone closes, update its status in `docs/ROADMAP.md`.
