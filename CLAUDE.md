# CLAUDE.md

mdv is a native macOS Markdown viewer with a CLI. Working name; the final name is chosen before M6.
Read `docs/VISION.md` (principles, architecture, security model) and `docs/ROADMAP.md` (milestones,
process) before planning work.

## Commands

```sh
make generate         # regenerate mdv.xcodeproj from project.yml (run after adding/removing files)
make test-core        # cli-docs, then swift test (MdvCore, CLI), no Xcode project needed
make cli-docs         # man page + zsh/bash/fish completions into build/cli-docs (generated, #71)
make test             # core + app unit tests (not UI tests)
make test-ui          # XCTest UI tests; always signed (team or ad hoc), drives the GUI
make record-theme-snapshots  # re-record bundled theme references for this macOS version (#39)
make build            # app + embedded CLI (signed via Config/Local.xcconfig); SIGN=0 for unsigned
make lint             # swiftlint --strict + swift format lint --strict (CI runs this)
make format           # auto-format; run before committing
make emoji            # regenerate Generated/EmojiTable.swift from github/gemoji (pinned commit)
make html-entities    # regenerate Generated/HTMLEntityTable.swift from the WHATWG entity list
make vendor-highlightjs  # re-vendor highlight.js (HLJS_VERSION=x.y.z) as generated Swift
make vendor-github-markdown-css  # re-vendor the GitHub theme (GHCSS_VERSION=x.y.z) as generated Swift
swift run mdv --html FILE   # render to stdout without Xcode
scripts/measure-cold-open [-f] [-c] FILE  # Release cold open to first paint, median of N launches
                                     # (GUI); -f adds the bare-WKWebView floor (scripts/cold-open-floor.swift),
                                     # -c times `open -n -a` against `mdv FILE` from the command's start
```

`.NOTPARALLEL` is set because the user's shell exports `MAKEFLAGS=-j9`; concurrent xcodebuilds
lock the build database.

## Layout

- `Sources/MdvCore`: all rendering logic (parse, transform, HTML, themes, preprocessors). No UI
  imports. New logic goes here so it is testable with `swift test`.
  - `Parsing/`: `MarkdownParser` wraps swift-cmark's C API (the only code that imports
    `cmark_gfm`); `MarkdownExtension` lists GFM extensions, which flavors enable.
  - `Flavors/`: `Flavor` (id, name, extensions, transforms; syntax only) with `gfm` (default)
    and `commonmark`; `FlavorRegistry` resolves ids (unknown → GFM). A flavor is one
    `static let` plus a line in `FlavorRegistry.bundled` plus `Fixtures/flavors/<id>/`.
  - `AST/`: `MarkdownNode`, our `Sendable` syntax tree (CommonMark + GFM kinds, source ranges).
  - `Rendering/`: `HTMLRenderer` walks the AST to HTML; `MarkdownRenderer`, `RenderOptions`, and
    `RenderedDocument` are the public API. `HTMLRenderer+Pipeline.swift` is the render pipeline
    (VISION): custom preprocessor (`SourcePreprocessor`, before `render(_:)`) → frontmatter →
    flavor resolution → parse → transforms → HTML. `RenderOptions.flavor` picks syntax;
    viewer features are separate toggles. `RenderOptions.spec` turns every mdv addition off; a
    new toggle adds one line there. Heading slugs, footnote ids, and `data-source-line` live here.
  - `Sanitizing/`: `HTMLSanitizer` allowlist for raw-HTML nodes only (renderer output is trusted,
    so everything the renderer emits must be escaped by construction).
  - `Frontmatter/`: YAML/TOML detection, Yams parsing with size/alias caps.
  - `Overrides/`: `DocumentOverrides` (#54), the frontmatter's `mdv:` mapping (`flavor`,
    `theme`, `wikilinks`), with ignored keys reported in `RenderedDocument.overrides`.
    `RenderOptions.applying(_:)` is the one place it changes a render (the flavor and the
    `.wikiLinks` built-in preprocessor only): never route a safety setting through it.
  - `Transforms/`: AST passes. `MarkdownTransform` (enum; declaration order is run order:
    alerts, wiki links, emoji) names each pass; its implementation conforms to
    `MarkdownTreeTransform`. Enabled by `Flavor.transforms` or
    `RenderOptions.builtInPreprocessors`. Emoji shortcodes and GitHub alerts (`GitHubAlerts`,
    top-level `> [!NOTE]` quotes to `MarkdownNode.Kind.alert`; markup and Octicons in
    `Rendering/HTMLRenderer+Alerts.swift`) live here, and so do wiki links (`WikiLinks`, #53:
    `[[Page]]` text to `MarkdownNode.Kind.wikiLink`; markup in `HTMLRenderer+WikiLinks.swift`).
  - `WikiLinks/`: wiki link pages and resolution (#53). `WikiPage` (the naming rule),
    `WikiLinkResolver` (injected into `HTMLRenderer.wikiLinkResolver`; the search rules never
    read the disk), `FolderWikiLinkResolver` (document folder, then allowed root, entry cap, over
    an injected `WikiLinkFolderReader`), `FileSystemFolderReader` (the real reader for the app
    and CLI: regular files and folders only, no symbolic links or packages), and `SourceLines`
    (which bracket bytes were written as is rather than escaped).
  - `Preprocessor/`: the custom preprocessor runner (#56; VISION's security model has the
    contract and limits). `CustomPreprocessor.run(input:documentURL:)` is async and
    cancellable. `PreprocessorConfiguration` validates the executable and
    `PreprocessorLimits` holds the bounds; failures are `PreprocessorError`.
    `PreprocessorEnvironment` builds the env and working directory, `PreprocessorProcess`
    calls `posix_spawn`, and `PreprocessorSession` is the kqueue I/O loop on a dedicated
    thread. `for(documentURL:)` is the pipeline's `SourcePreprocessor`. Every descriptor goes
    through `PreprocessorDescriptors`, which the leak tests count. Fixture scripts are in
    `Tests/MdvCoreTests/Fixtures/preprocessors`.
  - `Themes/`: `Theme` (CSS plus `ThemeBackground`), `ThemeRegistry` (the one place the app and
    CLI get a theme; unknown ids fall back to GitHub), `ThemeBase` (the base layer every page
    gets; `!important` there means protected from themes), and `ThemeLayer` (cascade layers
    `mdv-base` → `mdv-theme` → `mdv-user`, one `<style id>` each). Bundled themes are
    `extension Theme { static let … }` files here.
    `Themes/Custom/`: custom theme files (#35): `CustomTheme` (header, id), `CustomThemeCSS` (the
    safety check; `CustomThemeCSSScanner` tokenizes), `CustomThemeFolder` (reading the folder).
  - `LocalResources/`: the app's `mdv-doc://<token>/<path>` URLs (`DocumentURLScheme`), the
    allowed-root rule, `LocalImagePolicy`, which approves every local image read, and
    `RootRelativeURL` (`/docs/x.png` resolved against the allowed root, `RenderOptions.linkRoot`).
  - `RemoteImages/`: `RemoteImage` (what counts as remote), `RemoteImagePolicy`
    (`RenderOptions.remoteImages`), and the blocked-image placeholder markup.
  - `Navigation/`: `LinkPolicy`, the viewer's one navigation policy (link URL to `LinkAction`),
    and `CopyableLink` (what Copy Link copies; never an `mdv-doc:` URL).
  - `Outline/`: `DocumentOutline` (heading tree) and `OutlineTracker` (current section).
  - `Highlighting/`: highlight.js in JavaScriptCore; `HighlightValidator` re-serializes its output.
  - `AppOpening/`: what the CLI and the app agree on (M5; untrusted on the app's side).
    `AppOpenEvent` builds and reads the Open Documents event and its parameters
    (`AppOpenParameters`: `mdvT` theme, `mdvW` wait token in `+Wait`, with the
    `windowsClosed` notification name), and `StandardInputHandoff` writes, verifies, and takes
    the `cmd | mdv` handoff file.
  - `Generated/`, `*.generated.swift`: generator output (`make emoji`, `make html-entities`,
    `make vendor-highlightjs`); never edit by hand. `Vendor/` holds vendored sources with a
    MANIFEST and license.
- `App/`: the macOS app (module `MdvApp`), kept thin. AppKit lifecycle (`main.swift`,
  `AppDelegate`), SwiftUI for window content only. Feature folders: `ContentWidth/`, `Copy/`,
  `DefaultViewer/`, `Print/`, `RenderProgress/`, `Themes/`, `Zoom/` (each a small type plus its
  `DocumentWindowController+<Feature>.swift`). `Themes/ThemeSettings` holds the theme registry
  and the default for new windows; each window's theme is `DocumentWindowController.themeID`.
  `Themes/CustomThemeLibrary` watches the custom themes folder (`ThemeFolderWatcher`) and
  replaces the registry (`ThemeSettings.apply(_:)`). A window whose picked theme isn't
  registered shows Settings' default (`ThemeSettings.theme(forWindowThemeID:)`). The window
  resolves `themeID`: its View > Theme pick (`pickedThemeID`, the only theme restoration saves),
  else the document's `mdv.theme` (`documentThemeID`, from `RenderedPage`), else Settings'
  default when it opened (`newWindowThemeID`).
  - `Settings/`: `SettingsWindowController` (App menu > Settings…, a toolbar-style
    `NSTabViewController` of SwiftUI panes), `SettingsModel` (wraps the existing stores:
    `ThemeSettings`, `OutlinePreference`, `ZoomSettings`, `ContentWidthSettings`, the default
    viewer; stores nothing itself), and `GeneralSettingsView`. A new setting is a store with
    `init(defaults:isPersistent:)`, a property and `set…` method on the model, and a row.
    `MarkdownSettingsView` (#55) is Settings > Markdown: default flavor, frontmatter display,
    built-in preprocessors (one row per `MarkdownSettings.optionalPreprocessors` entry), then
    room for the custom preprocessor (#57).
  - `WikiLinks/`: `DocumentWikiLinks` (a per-render `FolderWikiLinkResolver` for a document,
    used by `DocumentContent` and Copy as HTML) over MdvCore's `FileSystemFolderReader`.
  - `MarkdownSettings/`: `MarkdownSettings` (the store: default flavor id, frontmatter
    display, built-in preprocessors; one change notification) and `MarkdownPreferences` (the
    value a render takes; `apply(to:)` sets `RenderOptions`). Unlike window defaults these
    apply to open documents: `MarkdownDocument` follows the store and re-renders in place, and
    `DocumentContent.preferences` records what a page was rendered with.
  - `CustomPreprocessor/` (#57): `CustomPreprocessorSettings` (store: on/off, executable,
    arguments, the session's `lastRun`; `shared` in memory under tests, or set by
    `-MdvUITestPreprocessor`), `CustomPreprocessorModel` (Settings' model: the enable warning,
    the Open panel), `DocumentContent.rendering(_:of:preferences:)` (the async render: runs the
    preprocessor, falls back to the unprocessed source with `preprocessorError`), and
    `PreprocessorFailureBar`. The setting reaches renders as
    `MarkdownPreferences.customPreprocessor` (`MarkdownDocument.renderPreferences`), so a change
    re-renders open documents like any Settings > Markdown change. The section view is
    `Settings/CustomPreprocessorSection`.
  - `CommandLineTool/` (#70): App menu > Install / Repair / Uninstall Command Line Tool….
    `CommandLineToolInstaller` (the rules over an injected folder and app: state, atomic
    install, uninstall, and the constant privileged shell scripts; an `Item` per linked file,
    the hook for #71), `PrivilegedRunning` (`AppleScriptPrivilegedRunner`, values passed as
    Apple event parameters), `CommandLineToolLocation` (`~/.local/bin`, `/usr/local/bin`, or
    the UI-test folder; `LoginShellPath`), and `CommandLineToolController` (menu state, alerts).
  - `Document/`: `MarkdownDocument` (`NSDocument`, viewer only) owns `DocumentContent` (source
    plus `RenderedPage`, and the remote-images variant). `read(from:ofType:)` reads and decodes
    on main (so open errors stay NSDocument's) and renders off the main actor
    (`render(_:of:)`; tests await `pendingRender`), so `content` is `nil` until the first render
    lands; a newer read, `setContent`, or `close()` drops and cancels a render in flight
    (stopping a custom preprocessor run). Every load and
    revert goes through `setContent(_:)`, which tells each `DocumentWindowController`
    (and re-renders content made with outdated Markdown settings, #55).
    `DocumentController` (the shared `NSDocumentController`) finds open files by identity,
    skips gone files on restore, types extensionless text files (`ExtensionlessText`) as
    plain text, and turns a verified standard input handoff into an untitled
    `MarkdownDocument(standardInput:)` (#68); its `canOpen(_:)` is the one rule for the Open
    panel and drops. `DocumentOpener` opens an Open Documents event's files (Finder, `open`,
    `mdv FILE`; `AppDelegate.application(_:open:)` and the direct `mdv /odoc` handler) with its
    parameters: `--theme` as each window's pick, `--wait` tokens through `WindowWaits` (#69).
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
    (default visibility). The window fills it after the first page paints (#58), then on each
    display.
  - `RenderProgress/`: `RenderProgress` (#58: the delayed indicator's state, 300 ms by default,
    injectable) and `RenderProgressIndicator` (the overlay: centered over the blank page before
    the first page loads, small in the corner during re-renders). The window feeds it from
    `isWaitingForFirstPage` and `MarkdownDocument.isRendering` (a render or live reload in
    flight; `updateRenderActivity()` tells each window).
  - `Window/`: `DocumentWindowController` (one per window, in the responder chain; feature
    actions go in `DocumentWindowController+<Feature>.swift`, menu validation in the one
    `validateMenuItem` switch in `+Outline.swift`), `DocumentWindow` (restorable state),
    `DocumentView` (SwiftUI root: find bar, file status and remote image bars, link status).
  - `WebView/`: `WebViewCoordinator` owns the `DocumentWebView` (drops, context menu trimming):
    `prepareForFirstLoad()` (a blank page while the first render runs), `load`, `updateContent`,
    and the async bridge (`readingPosition()`, `scroll(toSourceLine:)`,
    `scroll(toFragment:)`). `WebViewPrewarmer` starts the first window's web view at launch
    (#40). `WebViewConfiguration` holds preferences and user scripts;
    `LocalResourceSchemeHandler` serves `mdv-doc` images; `+Navigation.swift` applies
    `LinkPolicy`.
  - `Scripts/`: bundled JS run only in `AppScripts.world`; pass values as arguments, never
    splice them into source.
  - `Performance/`: `LaunchTiming`, launch milestones that `scripts/measure-cold-open` reads
    (on only with `MDV_LAUNCH_TIMING` set; kept in Release, which is what it measures).
  - `Menus/`: `MainMenu` builds the menu bar in code. A feature adds a `MenuContribution` type
    in its own file plus one line in `MainMenu.contributions`. AppKit inserts Open Recent and
    the Window menu's items itself; don't build them.
- `CLI/`: ArgumentParser `mdv` tool, embedded at `mdv.app/Contents/Helpers/mdv`.
  `CLI/MdvCLIKit` (library) is the command: `MdvCommand` (parse, cross-group `validate()`,
  mode pick, `execute(in: CLIEnvironment)`) plus one `@OptionGroup` file per concern
  (`InputOptions`, `OutputOptions`, `ThemeFlavorOptions`, `RenderFlagOptions`,
  `PreprocessorOptions`, `AppOpenOptions`), `MdvCommand+HTML` (headless output),
  `MdvCommand+App` and `AppOpening` (opening in the app), `ExitStatus` (sysexits codes, listed
  in `--help`), and `CLIError` (one `mdv: …` stderr line plus a status). `CLI/Main` is the
  executable (SwiftPM `MdvCLI`, Xcode `mdv-cli`) and only calls `MdvCommand.main()`. A new flag
  goes in its concern's group file; never read the process's streams directly (use
  `CLIEnvironment`). Completions and the man page (#71) are generated from the command, so a
  flag needs nothing more (give a path or id value a `completion:`). Text `--help` and the man
  page share lives in `HelpText` (overview, examples) and `ExitStatus.entries`; `ManualPage`
  finishes generate-manual's page with the hand-written sections, run by the `CLI/ManualTool`
  build tool (`MdvManualTool`, not shipped) from `make cli-docs`. Opening in the app:
  `WorkspaceAppOpener` (Launch Services, or the direct event to our running copy) with
  `AppLocator` (which app), `WindowsClosedWaiter` and `DarwinNotification` (`--wait`), and the
  stdin handoff; `InterruptCancellation` turns signals into cancellation around a preprocessor
  run.
- `Tests/MdvCLITests`: CLI tests under `swift test`. `CLIHarness.run` parses and runs the command
  in-process against a fake `CLIEnvironment` (captured streams, `RecordingAppOpener`);
  `CLIBinary.run` runs the built `mdv` with stdin and captures stdout, stderr, and the status.
  `TempFolder` is a per-test folder; fixtures are in `Fixtures/`. `ReadmeExampleTests` runs
  every `mdv` command in the README's `sh` blocks (#72): a README example must be one its
  shell reader (`Support/ReadmeExamples.swift`) understands, and must work. Tests reading the
  generated man page and completions need `MDV_CLI_DOCS` (`make test-core` sets it).
- `Tests/MdvCoreTests`, `AppTests/`: Swift Testing (`import Testing`, `@Test`, `#expect`).
  `AppTests/Support/`: `DocumentWindowTestCase` (windows over temp files and throwaway
  settings), `ThrowawayDefaults` (a per-test `UserDefaults` suite in a temp folder; never use
  `UserDefaults(suiteName:)` with a plain name, which leaves a plist in ~/Library/Preferences),
  `MainThreadHeartbeat` (main-thread stalls by CPU time), `expectTiming` (`MainThreadTiming`: main-thread
  timing bounds, strict locally, report-only on CI via `TEST_RUNNER_MDV_TIMING_REPORT_ONLY`), `SnapshotImage`, `LoopbackServer`,
  `PreprocessorScripts` (custom preprocessor scripts plus a leaked-process check).
  `StressTests` (+`Themes`, `ZoomWidth`, `Preprocessor`, `Markdown`, `CommandLine`) is the crash and hang suite; run it
  under ASan and TSan at each milestone close-out (`-enableAddressSanitizer YES` / `-enableThreadSanitizer YES`).
- `AppUITests/`: XCTest UI tests (see "UI tests" below). `App/Testing/UITestHooks.swift` holds
  the Debug-only launch hooks they use.
- `docs/THEMES.md`: the end-user theme authoring guide, with `docs/example-theme.css` and
  `docs/github-soft-dark.css` (an `extends: github` example).
  `ThemeGuideTests` loads the example and checks the guide's snippets, limits, and error
  messages; a change to custom theme behavior updates the guide.
- `Tests/MdvCoreTests/Fixtures/spec`: vendored CommonMark/GFM spec examples, run in
  `RenderOptions.spec` mode. `exceptions.json` lists known failures (`pending #N` or `permanent`);
  a feature issue deletes its `pending` entries once they pass (the test fails on stale entries).
- `Tests/MdvCoreTests/Fixtures/flavors/<id>/`: per-flavor corpus (`FlavorCorpusTests`), `.md`
  inputs and recorded `.html` (`MDV_RECORD_SNAPSHOTS=1`); one folder per registered flavor. A
  feature that changes a flavor's output adds fixtures to it.
- `Tests/MdvCoreTests/Fixtures/flavors/<id>`: per-flavor corpus (`FlavorCorpusTests`,
  `MDV_RECORD_SNAPSHOTS=1`). `Fixtures/github/alerts.md` is github.com's alert rules from
  `gh api markdown` (mode gfm), compared normalized (see that folder's README).
- `Tests/MdvCoreTests/Fixtures/github`, `.../corpus`: GitHub reference output (refresh with
  `scripts/update-github-fixtures`, manual, needs auth) and mdv snapshots
  (`MDV_RECORD_SNAPSHOTS=1`). Corpus exceptions live in `corpus.json`.
- `AppTests/Snapshots/macOS-<major>/`: visual regression references for the bundled themes
  (`ThemeSnapshotTests`: showcase fixture, each theme light/dark/print, real WebKit PDFs
  rasterized at 1 px per point). One set per macOS major (CI is macOS 26). After an intended
  theme change, `make record-theme-snapshots` on each OS and review the PNG diff; macOS 26
  references come from CI's `theme-snapshots` artifact (`recorded/`). Mismatches write
  actual/reference/diff PNGs to `build/theme-snapshots/` (CI uploads it).
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
  plist array, `launch(openingFixtures:)`) opens documents at launch; `-MdvUITestThemesFolder
  <abs path>` reads custom themes from a temp folder (UI tests without it load none, and hosted
  unit tests never load them); `-MdvUITestPreprocessor <abs path>` starts with that custom
  preprocessor on; `-MdvUITestRenderDelay <seconds>` holds up every render (to see the
  slow-render indicator without a slow script); `-MdvUITestCommandLineToolFolder <abs path>`
  is the only folder Install Command Line Tool… offers (none without it). UI tests that run the
  CLI (`MdvUITestApp+CommandLine`, `+Wait`) use the built app's helper; the runner is
  sandboxed, so Launch Services refuses it and the CLI falls back to the direct event
  (`AppUITests.entitlements` allows it), fixtures are copied to temp first, and standard input
  comes from a file, never a pipe. Preprocessor scripts are executable fixtures
  (`Fixtures/preprocessors/`): files the sandboxed runner writes are quarantined and won't
  execute (`EPERM`). Tests never add to Open Recent. `MdvUITestApp.launch` also passes `-ApplePersistenceIgnoreState YES` unless
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

- GitHub: `itspriddle/mdv` (public). Each roadmap milestone is a GitHub milestone with
  issues.
- One branch per issue (Conventional Branch, e.g. `feature/gfm-tables`), Conventional Commits
  (see `.claude/skills`). Issue branches merge into a milestone integration branch
  (e.g. `feature/m1-core-rendering`), which goes to `main` as one PR that must pass CI.
- After an issue lands, post a handoff comment (API changes, gotchas, deviations, deferred items)
  on the next issue or the milestone's tracking issue.
- When a milestone closes, update its status in `docs/ROADMAP.md`.
