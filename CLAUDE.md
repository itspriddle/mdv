# CLAUDE.md

mdv is a native macOS Markdown viewer with a CLI. Working name; the final name is chosen before M6.
Read `docs/VISION.md` (principles, architecture, security model) and `docs/ROADMAP.md` (milestones,
process) before planning work.

## Commands

```sh
make generate         # regenerate mdv.xcodeproj from project.yml (run after adding/removing files)
make test-core        # swift test (MdvCore), fast, no Xcode project needed
make test             # core + app unit tests (not UI tests)
make test-ui          # XCTest UI tests; always signed (team or ad hoc), drives the GUI
make build            # app + embedded CLI (signed via Config/Local.xcconfig); SIGN=0 for unsigned
make lint             # swiftlint --strict + swift format lint --strict (CI runs this)
make format           # auto-format; run before committing
make emoji            # regenerate Generated/EmojiTable.swift from github/gemoji (pinned commit)
make vendor-highlightjs  # re-vendor highlight.js (HLJS_VERSION=x.y.z) as generated Swift
swift run mdv --html FILE   # render to stdout without Xcode
```

`.NOTPARALLEL` is set because the user's shell exports `MAKEFLAGS=-j9`; concurrent xcodebuilds
lock the build database.

## Layout

- `Sources/MdvCore`: all rendering logic (parse, transform, HTML, themes, preprocessors). No UI
  imports. New logic goes here so it is testable with `swift test`.
  - `Parsing/`: `MarkdownParser` wraps swift-cmark's C API (the only code that imports
    `cmark_gfm`); `MarkdownExtension` lists GFM extensions toggled via `RenderOptions`.
  - `AST/`: `MarkdownNode`, our `Sendable` syntax tree (CommonMark + GFM kinds, source ranges).
  - `Rendering/`: `HTMLRenderer` walks the AST to HTML; `MarkdownRenderer`, `RenderOptions`, and
    `RenderedDocument` are the public API. `RenderOptions.spec` turns every mdv addition off; a
    new toggle adds one line there. Heading slugs, footnote ids, and `data-source-line` live here.
  - `Sanitizing/`: `HTMLSanitizer` allowlist for raw-HTML nodes only (renderer output is trusted,
    so everything the renderer emits must be escaped by construction).
  - `Frontmatter/`: YAML/TOML detection, Yams parsing with size/alias caps.
  - `Transforms/`: AST passes (emoji shortcodes).
  - `Themes/`: `Theme` (CSS plus `ThemeBackground`), `ThemeRegistry` (the one place the app and
    CLI get a theme; unknown ids fall back to GitHub), `ThemeBase` (the base layer every page
    gets; `!important` there means protected from themes), and `ThemeLayer` (cascade layers
    `mdv-base` → `mdv-theme` → `mdv-user`, one `<style id>` each). Bundled themes are
    `extension Theme { static let … }` files here.
  - `LocalResources/`: the app's `mdv-doc://<token>/<path>` URLs (`DocumentURLScheme`), the
    allowed-root rule, `LocalImagePolicy`, which approves every local image read, and
    `RootRelativeURL` (`/docs/x.png` resolved against the allowed root, `RenderOptions.linkRoot`).
  - `RemoteImages/`: `RemoteImage` (what counts as remote), `RemoteImagePolicy`
    (`RenderOptions.remoteImages`), and the blocked-image placeholder markup.
  - `Navigation/`: `LinkPolicy`, the viewer's one navigation policy (link URL to `LinkAction`),
    and `CopyableLink` (what Copy Link copies; never an `mdv-doc:` URL).
  - `Outline/`: `DocumentOutline` (heading tree) and `OutlineTracker` (current section).
  - `Highlighting/`: highlight.js in JavaScriptCore; `HighlightValidator` re-serializes its output.
  - `Generated/`, `*.generated.swift`: generator output (`make emoji`, `make vendor-highlightjs`);
    never edit by hand. `Vendor/` holds vendored sources with a MANIFEST and license.
- `App/`: the macOS app (module `MdvApp`), kept thin. AppKit lifecycle (`main.swift`,
  `AppDelegate`), SwiftUI for window content only. Feature folders: `Copy/`, `DefaultViewer/`,
  `Print/`, `Zoom/` (each a small type plus its `DocumentWindowController+<Feature>.swift`).
  - `Document/`: `MarkdownDocument` (`NSDocument`, viewer only) owns `DocumentContent` (source
    plus `RenderedPage`, and the remote-images variant). `read(from:ofType:)` reads and decodes
    on main (so open errors stay NSDocument's) and renders off the main actor
    (`render(_:of:)`; tests await `pendingRender`), so `content` is `nil` until the first render
    lands; a newer read, `setContent`, or `close()` drops a render in flight. Every load and
    revert goes through `setContent(_:)`, which tells each `DocumentWindowController`.
    `DocumentController` (the shared `NSDocumentController`) finds open files by identity,
    skips gone files on restore, and types extensionless text files (`ExtensionlessText`) as
    plain text; its `canOpen(_:)` is the one rule for the Open panel and drops.
  - `Find/`: `FindInPage` (find state and commands, tested with a fake host), `SharedFindQuery`
    (the system find pasteboard), and `FindBar`
    (SwiftUI bar; the field is an `NSSearchField` whose field editor passes Edit > Find
    commands on). The page side is `App/Scripts/FindInPage.js` via `WebViewCoordinator+Find`.
  - `LiveReload/`: `FileWatcher` (kqueue by path, debounced; watches the nearest existing
    ancestor while the folder is gone) and `LiveReloader` (reads and
    renders off the main actor, drops stale renders, sets `MarkdownDocument.fileStatus`). Live
    reload bypasses `NSDocument.revert`; the window swaps content in place with
    `WebViewCoordinator.updateContent(with:baseURL:)`, which keeps the reading position.
  - `Outline/`: `OutlineViewController` (the sidebar's `NSOutlineView`) and `OutlinePreference`
    (default visibility).
  - `Window/`: `DocumentWindowController` (one per window, in the responder chain; feature
    actions go in `DocumentWindowController+<Feature>.swift`, menu validation in the one
    `validateMenuItem` switch in `+Outline.swift`), `DocumentWindow` (restorable state),
    `DocumentView` (SwiftUI root: find bar, file status and remote image bars, link status).
  - `WebView/`: `WebViewCoordinator` owns the `DocumentWebView` (drops, context menu trimming):
    `prepareForFirstLoad()` (a blank page while the first render runs), `load`, `updateContent`,
    and the async bridge (`readingPosition()`, `scroll(toSourceLine:)`,
    `scroll(toFragment:)`). `WebViewConfiguration` holds preferences and user scripts;
    `LocalResourceSchemeHandler` serves `mdv-doc` images; `+Navigation.swift` applies
    `LinkPolicy`.
  - `Scripts/`: bundled JS run only in `AppScripts.world`; pass values as arguments, never
    splice them into source.
  - `Menus/`: `MainMenu` builds the menu bar in code. A feature adds a `MenuContribution` type
    in its own file plus one line in `MainMenu.contributions`. AppKit inserts Open Recent and
    the Window menu's items itself; don't build them.
- `CLI/`: ArgumentParser `mdv` tool (module `MdvCLI`), built both by SwiftPM and by the Xcode
  `mdv-cli` target, embedded at `mdv.app/Contents/Helpers/mdv`.
- `Tests/MdvCoreTests`, `AppTests/`: Swift Testing (`import Testing`, `@Test`, `#expect`).
- `AppUITests/`: XCTest UI tests (see "UI tests" below). `App/Testing/UITestHooks.swift` holds
  the Debug-only launch hooks they use.
- `Tests/MdvCoreTests/Fixtures/spec`: vendored CommonMark/GFM spec examples, run in
  `RenderOptions.spec` mode. `exceptions.json` lists known failures (`pending #N` or `permanent`);
  a feature issue deletes its `pending` entries once they pass (the test fails on stale entries).
- `Tests/MdvCoreTests/Fixtures/github`, `.../corpus`: GitHub reference output (refresh with
  `scripts/update-github-fixtures`, manual, needs auth) and mdv snapshots
  (`MDV_RECORD_SNAPSHOTS=1`). Corpus exceptions live in `corpus.json`.
- `project.yml`: XcodeGen spec. Never commit `mdv.xcodeproj`; edit `project.yml` instead.
- `Config/Shared.xcconfig`: shared settings. `Config/Local.xcconfig` (gitignored) holds
  `DEVELOPMENT_TEAM`; never commit it or hard-code the team ID.

## Conventions

- Swift 6 language mode, strict concurrency, macOS 15 minimum.
- Lint and format must pass with zero violations; swift-format owns layout, SwiftLint owns smells.
- No force unwraps; prefer failable APIs (e.g. `String(bytes:encoding:)`) and throw on bad input.
- Security defaults from `docs/VISION.md` are requirements: strict CSP, no remote content, JS off
  or bundle-only, sanitize raw HTML, user scripts are opt-in.
- Bundle ID placeholder `com.itspriddle.mdv` lives in `PRODUCT_BUNDLE_IDENTIFIER_BASE`,
  `MdvCommand.appBundleIdentifier`, and the exported UTI `MarkdownContentTypes` (an app test
  checks it); keep them in sync. Same for `MARKETING_VERSION` and `MdvInfo.version`.
- Verify a dependency exists (and its latest version) before adding it.

## UI tests

- `AppUITests` (XCTest; Swift Testing has no UI API) drives the built app. Every M2+ feature with
  a user-facing flow adds a test here. Fixtures live in `AppUITests/Fixtures/` (a folder
  reference; `Fixtures.url(named:)`).
- Use `MdvUITestApp` (`AppUITests/Support/`): `launch(openingFixture:)`, `waitForWindow(titled:)`,
  `webView(in:)`, `waitForRenderedText(_:in:)`. Add feature helpers in
  `Support/MdvUITestApp+<Feature>.swift`. Classes are `@MainActor final class ...: XCTestCase`.
- Launch hooks (`UITestHooks`, `#if DEBUG` only, compiled out of Release): `-MdvUITesting YES`
  skips the launch Open panel and suppresses first-run prompts (features with a first-run prompt
  must check `UITestHooks.suppressesFirstRunPrompts`); `-MdvUITestOpen <abs path>` (or a
  plist array, `launch(openingFixtures:)`) opens documents at launch. Tests never add to Open
  Recent. `MdvUITestApp.launch` also passes `-ApplePersistenceIgnoreState YES` unless
  `restoresState: true`; the restoration UI test writes real saved state, so it runs only with
  `TEST_RUNNER_MDV_UI_TEST_RESTORATION=1 make test-ui` (CI sets it).
- The UI test runner must be code signed: `make test-ui` ignores `SIGN` and signs with the team
  in `Config/Local.xcconfig`, else ad hoc. Never run UI tests unsigned (Gatekeeper pops a
  "can't run" dialog for every attempt).
- Local setup: the app that runs `make test-ui` (Terminal, iTerm, Claude Code's host) needs
  System Settings > Privacy & Security > Developer Tools, or Gatekeeper kills the runner
  ("Test crashed with signal kill before establishing connection"; log shows "Gatekeeper policy
  blocked execution"). The first run asks to allow `AppUITests-Runner` Accessibility access.
- Debugging: failures leave `build/AppUITests.xcresult` (screenshots, logs, UI hierarchy);
  `open build/AppUITests.xcresult`. Run one test with
  `xcodebuild ... test -only-testing:AppUITests/SmokeUITests/testOpensFixtureWithTitleAndRenderedText`
  or from Xcode (`make generate`, open `mdv.xcodeproj`, scheme `mdv`). `app.debugDescription`
  prints the accessibility tree. CI uploads the result bundle on failure.
- The Xcode app target is `MdvApp` (product `mdv.app`): a target named `mdv` collides with the
  SwiftPM `mdv` executable, and the UI test runner then launches the CLI.

## Workflow

- GitHub: `itspriddle/mdv` (private until 1.0). Each roadmap milestone is a GitHub milestone with
  issues.
- One branch per issue (Conventional Branch, e.g. `feature/gfm-tables`), Conventional Commits
  (see `.claude/skills`). Issue branches merge into a milestone integration branch
  (e.g. `feature/m1-core-rendering`), which goes to `main` as one PR that must pass CI.
- After an issue lands, post a handoff comment (API changes, gotchas, deviations, deferred items)
  on the next issue or the milestone's tracking issue.
- When a milestone closes, update its status in `docs/ROADMAP.md`.
