# Roadmap

Milestones are ordered by dependency. Each one becomes a GitHub milestone, then gets broken down
into issues in its own planning session. Scope lists are starting points, not contracts. Refine
them when the milestone is broken down.

| Milestone                               | Theme                          | Release   | Status |
| --------------------------------------- | ------------------------------ | --------- | ------ |
| [M0](#m0-foundation)                    | Foundation                     | -         | Done   |
| [M1](#m1-core-rendering)                | Core rendering                 | -         | Done   |
| [M2](#m2-viewer-app)                    | Viewer app                     | -         | Done   |
| [M3](#m3-themes)                        | Themes                         | -         | Done   |
| [M4](#m4-flavors-and-preprocessors)     | Flavors and preprocessors      | -         | Done   |
| [M5](#m5-cli)                           | CLI                            | -         | Done   |
| [Gate](#gate-choose-the-name)           | Choose the final name          | -         | Done   |
| [M6](#m6-distribution-and-v010)         | Distribution                   | **0.1.0** |        |
| [1.0](#10)                              | PDF, math, RTL, proofreading…  | 1.0       |        |

## M0: Foundation

**Status:** Done (2026-11-06).

Get a buildable, tested, linted walking skeleton and a shared plan.

- Swift package `PeepCore` with a minimal renderer (swift-markdown `HTMLFormatter`) and tests
- SwiftUI app that opens `.md` files read-only and renders them in a `WKWebView`
- `peep` CLI target embedded in the app bundle; `--html` and `--version` work
- XcodeGen `project.yml`, xcconfig-based settings with a gitignored local signing override
- SwiftLint + swift-format, `Makefile`, GitHub Actions CI
- `docs/VISION.md`, `docs/ROADMAP.md`, `README.md`

**Exit criteria:** `make lint test build` passes locally and in CI. ✅

## M1: Core rendering

**Status:** Done (2026-11-06).

Make the rendered output correct and complete.

- Parse with swift-cmark into our own AST and render HTML from it, replacing swift-markdown
- CommonMark + GFM: tables (with alignment), strikethrough, autolinks, task list checkboxes,
  footnotes
- Heading anchors (GitHub-compatible slugs) and duplicate handling
- Frontmatter: detect YAML (`---`) and TOML (`+++`); parse YAML with
  [Yams](https://github.com/jpsim/Yams); hide by default, optionally render as a table; expose
  values (e.g. `title`) to the app
- Emoji shortcodes (`:tada:`) using the GitHub emoji set
- Raw HTML policy: allowlist sanitizer; dangerous tags and attributes removed
- Syntax highlighting for fenced code blocks
- Source line annotations (`data-source-line`) to enable scroll sync later
- Golden/snapshot test corpus (CommonMark spec, GFM spec samples, real-world READMEs), stress
  and fuzz tests

**Decisions:**

- Parse with `swiftlang/swift-cmark` (cmark-gfm) directly, not swift-markdown, which can't enable
  GFM autolinks or footnotes and forces smart punctuation. Our own `MarkdownNode` AST and
  `HTMLRenderer` sit on top.
- Syntax highlighting is native, at render time: a vendored, pinned highlight.js (BSD-3) in
  JavaScriptCore inside `PeepCore`, emitting static class-based spans, so `--html` works and the
  viewer keeps JavaScript off.
- Raw HTML goes through our own allowlist sanitizer modeled on GitHub's (no SwiftSoup); it only
  touches raw-HTML nodes, since renderer output is trusted.
- TOML frontmatter is detected and hidden but not parsed; YAML is parsed with Yams.
- The README corpus is compared with github.com's file view (contents API,
  `application/vnd.github.html`); neither `POST /markdown` mode matches it.
- Generated ids are unique per document: on a collision, footnote ids yield and heading slugs
  keep their GitHub value.

**Exceptions:** [spec](../Tests/PeepCoreTests/Fixtures/spec/exceptions.json) (GFM `tagfilter`
only, permanent: the sanitizer replaces it) and
[README corpus](../Tests/PeepCoreTests/Fixtures/corpus/README.md#exceptions).

**Exit criteria:** GFM spec examples pass (or have documented exceptions); a representative
corpus of READMEs renders to match GitHub; renderer is fuzz/stress tested on large inputs. ✅

## M2: Viewer app

**Status:** Done (2026-11-06).

A pleasant, Mac-native document viewer.

- Open via Finder, Open dialog, drag and drop, recents, Dock; tabs; window restoration
- Offer to become the default `.md` handler
- Live reload on file change, preserving the reading position
- Relative images and links resolve against the file, with scoped file access
- Link handling: local `.md` opens in Peep, anchors scroll, external URLs open in the browser;
  a navigation policy for every other link
- Remote images blocked by default, with a per-window opt-in
- Find in page, zoom (Cmd +/-/0), print, copy as HTML / Markdown source
- Outline / table-of-contents sidebar from headings
- Light/dark appearance following the system
- UI tests for the core flows (open, links, images, reload, outline, find, zoom/copy), in CI

**Decisions** (details and rationale in [VISION](VISION.md#architecture-overview)):

- **Document architecture (#16):** AppKit `NSDocument`/`NSDocumentController` hosting SwiftUI
  window content, with an AppKit app lifecycle and a code-built menu (per-feature
  `MenuContribution`s), not SwiftUI `DocumentGroup`, which hides file presenters, revert, the
  window controller, restoration, and the responder chain. Positions are fractional source
  lines. App scripts are bundled `.js` run in an isolated content world; page JS stays off.
- **UI tests (#17):** an XCTest `AppUITests` target in its own CI job, driven by Debug-only
  launch hooks (`UITestHooks`); the Xcode app target is `PeepApp` so the runner doesn't launch
  the SwiftPM `peep` CLI.
- **Local resources (#18):** a `WKURLSchemeHandler` (`peep-doc://<window token>/<absolute
  path>`), not `loadFileURL` plus a temp file; it serves only images that `LocalImagePolicy`
  approves inside the allowed root, the enclosing git work tree or else the document's folder
  (never home or `/`); extension and sniffed format must match. Root-relative `/x` links and
  images resolve against that root, as on GitHub, and `#gh-dark-mode-only` /
  `#gh-light-mode-only` images follow the appearance (CSS).
- **Links (#19):** one tested `LinkPolicy`; the main frame never leaves the document. Local
  Markdown opens in Peep (Cmd-click or middle-click: a new tab); other local files and folders
  are revealed in Finder, never opened; `http`/`https`/`mailto` open in the default app; other
  schemes are blocked silently with the reason in the link status overlay. Fragments try the
  raw id, the decoded id, then `user-content-`. Raw HTML headings get GitHub-style anchors.
- **Remote images (#20):** blocked in `PeepCore` (labeled placeholders) and by the CSP; the
  opt-in is per window, unsaved, and `https:` only; the bar appears only when an `https:` image
  was blocked. `peep --html` keeps remote images by default (its CSP blocks them when opened).
- **Live reload (#21):** a kqueue watcher by path (measured: `NSFilePresenter` reported other
  apps' edits ~1 s late and went silent after a delete), reading and rendering off the main
  actor, bypassing `NSDocument.revert`; an in-place body swap that keeps the reading position
  (reload-and-restore only when the file moved). Renames are followed; a move to the Trash is
  a deletion; the last render stays under a banner when the file is deleted or unreadable.
- **Opening (#22):** an already-open file is found by identity and focused; drops on a window
  open as tabs; tabs follow the system "Prefer tabs" setting; restoration (including each
  window's reading position) follows the system "Close windows when quitting" setting, so
  `peep FILE` doesn't bring back old windows (confirmed with the user); with no windows, launch
  and Dock click show the Open panel; plain text opens but is never claimed; `.mdown`/`.mkd`/
  `.mkdn` are Peep's own exported type (the system Markdown type lists only `.md`/`.markdown`).
- **Default handler (#23):** `LSHandlerRank` stays `Alternate`; Peep offers once in a
  non-modal panel ("Not Now" snoozes 30 days, "Don't Ask Again" is permanent) and has an app
  menu item until Settings exists.
- **Outline (#24):** an AppKit `NSOutlineView` sidebar split item (arrows browse, Return or
  click jumps), collapsible, hidden by default; the last toggle is the default for new
  windows, and visibility is restored per window.
- **Find (#25):** an app script with match counts and highlight-all via the CSS Custom
  Highlight API, not `WKWebView.find` (no count) or `NSTextFinder` (no public `WKWebView`
  integration); standard `performTextFinderAction(_:)` commands; it re-runs after reloads.
- **Zoom, print, copy (#26):** one app-wide, persisted zoom level for Cmd +/-/0, with pinch as
  a per-window magnification override; print through `NSDocument` and the print panel (Save
  as PDF) with `@media print` rules that always use light colors; Copy as HTML copies the
  `peep --html` body fragment; the web view's context menu drops browser-only items
  (a blocklist, so new system items keep working).
- **Close-out (#27):** AppKit inserts and maintains Open Recent (a code-built one can't be
  marked as the recents menu and showed up twice). The first open of a document still reads
  and renders on the main thread (below); moving it off main needs a background `NSDocument`
  init, which the SDK's `@MainActor` annotation on `NSDocument` traps at runtime under Swift
  6, so it is deferred to M3.

**Crash and hang pass (#27):** `AppTests` (183 tests, including a stress suite: many windows
opened, reloaded, and closed mid-load; files deleted, renamed, and rewritten while open; a
removed folder; malformed and non-UTF-8 files) and `AppUITests` pass under Address Sanitizer
and Thread Sanitizer in Debug with no reports; `PeepCoreTests` under both sanitizers fail only
their wall-clock budgets (sanitizer slowdown). `make test-ui` passed 5 consecutive runs locally
(20 tests, the opt-in restoration test skipped) with no retries; CI (macOS 26, Xcode 26.6)
runs the full UI suite, including restoration, and was green on the merged PR (#28).

**Performance (#27):** cold window open to first paint, measured from process start (the
kernel's start time) to two animation frames after the first page load finished, Release
build, Apple silicon, median of 6 launches with the file as an argument:

| Document | Size | First open read + render (main thread) | Cold open to first paint |
| -------- | ---- | -------------------------------------- | ------------------------ |
| peep README | 1.7 KB | 3 ms | 372 ms |
| `bat` README (corpus) | 34 KB | 8 ms | 422 ms |
| Synthetic (code, tables, lists) | 1 MB | 161 ms | 737 ms |
| Synthetic | 5 MB | 392 ms | 1816 ms |

For the README, the time is about 90 ms to the document read, 60 ms creating the web view,
70 ms building the window (split view, SwiftUI hosting), 100 ms loading the page (including
launching the WebContent process), and 100 ms to the painted frame. That misses VISION's
200 ms; a web view pre-warmed at launch saved only ~40 ms. Follow-up in M3.

**Exit criteria:** daily-drivable for reading local docs; no known crashes; UI tests in CI.
✅ (automated checks; the manual daily-driver checklist is in the #27 handoff)

## M3: Themes

**Status:** Done (2026-11-07).

CSS themes as a first-class feature.

- Bundled themes: GitHub (Primer, light and dark), a word-processor style ("Document"), minimal/serif
- Theme model in `PeepCore`: name, stylesheet(s), light/dark variants, optional print CSS
  (print themes; M2 ships basic `@media print` rules); owns the highlight.js token CSS
- Custom themes: CSS files in `~/Library/Application Support/Peep/Themes`, hot-reloaded
- Theme picker per window plus a global default in a Settings window
- Content width controls layered on top of any theme (font size dropped: zoom covers it, #37)
- Theme authoring guide (the only doc written for end users before 1.0)
- Viewer follow-ups from M2:
  - Settings window: theme default, outline default, zoom; move "Make Peep the Default
    Markdown Viewer" there; optionally remember the remote image opt-in per file (deferred, #36)
  - Performance: cold open to first paint under 200 ms for README-sized docs (422 ms in M2;
    replaced by the agreed `WKWebView` floor, #40),
    and the first open's read and render off the main thread (161 ms for 1 MB)
  - Smaller viewer polish, filed as issues: a document folder deleted and recreated isn't
    noticed; extensionless files (`README`) can't be opened from the Open panel; "Copy Link"
    on a relative link copies the internal `peep-doc:` URL; the find pasteboard

**Decisions:**

- CSS layering (#31): cascade layers, `@layer peep-base, peep-theme, peep-user`, one `<style>` per
  layer. The base layer's `!important` rules (find highlights, placeholders, light/dark-only
  images, structural print rules) can't be undone by any theme; see VISION.
- GitHub theme source (#33): vendor `sindresorhus/github-markdown-css` (MIT, pinned 5.9.0,
  `make vendor-github-markdown-css`), adjusted to screen-only dark and no `url()`; highlight.js
  tokens use its Primer syntax variables. The Docs-style theme is named "Document" (id `document`);
  the serif theme is "Serif" (id `serif`).
- Font size vs zoom (#37): no font size control; zoom (Cmd +/-, reflowing `pageZoom`) is the
  text size control. Content width is four presets (narrow, theme default, wide, full) in
  View > Content Width, global and persisted, applied live via the `peep-user` layer
  (`--peep-content-width`); print ignores it. See VISION. **Reversed after M3 (#47):** zoom and
  content width move to per window, like themes, with Settings setting the default for new
  windows. A global change re-laid out every open window at once, which was jarring. Landed;
  VISION's #26 and #37 entries record it.

- Theme switch (#34): in-place swap of the `peep-theme` `<style>` text by app script (same
  `peep.replaceStyle` as #37), keeping the reading position, find, zoom, and remote-image
  opt-in; no reload. Theme is per window (restorable); the default for new windows is set in
  Settings (#36). Print uses the window's theme; Copy as HTML stays theme-free.
- Custom theme metadata (#35): an optional leading `/* peep-theme … */` header comment with
  `name`, `background`, `background-dark` (hex), and `extends` (a bundled id; default: base layer
  only). Ids are `custom:<file name>`. `@import`, `expression()`, non-`data:image` URLs, and
  unbalanced brackets reject the file (shown disabled in the picker with the reason) rather than
  being stripped; `data:image/…` URLs are allowed. Regular files only (no symlinks), 512 KB,
  UTF-8, 100 themes. kqueue folder watch, 100 ms debounce; see VISION.
- Print themes (#38): paper always light (protected `print-color-adjust: economy` on the page,
  dark rules screen only); bundled themes keep light code/table fills on paper and print body
  text at about 12pt (Serif 15px on paper). `<picture>` dark sources are left to WebKit, which
  prints the light one. See VISION.
- Settings window (#36): an `NSWindowController` with a toolbar-style `NSTabViewController` of
  SwiftUI forms (no SwiftUI `Settings` scene). General: appearance (System, Light, or Dark,
  app-wide via `NSApp.appearance`; also View > Appearance), default theme (Settings owns it; View >
  Theme changes one window), outline in new windows, zoom, content width, Open Themes Folder,
  Make Peep the Default Markdown Viewer (moved from the app menu). It surfaces the existing
  stores rather than duplicating them. The remote-image opt-in is not remembered per file
  (deferred; a stored allowlist is a privacy record and a standing exception to "no remote
  content"). See VISION.
- Visual regression (#39): hosted `AppTests` (`ThemeSnapshotTests`) render the showcase fixture in
  each bundled theme, light, dark, and print, as real WebKit PDFs (`WKWebView.pdf` for screen,
  Save as PDF for print) rasterized at 1 px per point, and compare with committed PNGs per macOS
  major (`AppTests/Snapshots/macOS-26`, `macOS-27`), with a per-pixel tolerance plus a 3x3
  neighborhood for antialiasing and a 40-pixel budget. Re-record with
  `make record-theme-snapshots`; CI records a missing macOS 26 set as an artifact. See VISION.
- Theme authoring guide (#44): `docs/THEMES.md`, linked from the README, with a complete
  example theme in `docs/example-theme.css`. A core test (`ThemeGuideTests`) loads the example,
  checks that the guide embeds it verbatim, runs every CSS snippet through the custom theme
  check, and matches the quoted error messages and limits against the code.
- 200 ms (#40, accepted at the close-out): not reachable with `WKWebView`; the agreed target is
  the floor instead: Peep's cold open stays within about 0-50 ms of the floor's, measured in the
  same run. The floor is a
  bare AppKit app that loads the same page into one `WKWebView` (configured like Peep's) first
  thing at launch, in one plain window (`scripts/cold-open-floor.swift`). Peep is now within
  0-50 ms of it (run to run), and what remains is mostly WebKit's: the web content process takes about 130 ms from the first load to a
  finished page, and the first frames another 40-90 ms, after AppKit is up (about 45 ms) and the
  web view exists (about 50 ms). Peep starts its first window's web view first thing at launch
  (`WebViewPrewarmer`), so that bring-up overlaps the rest of the launch, the document read, and
  the window build. A regression is anything clearly slower than the floor, measured in the same
  sitting (`scripts/measure-cold-open -f`). See VISION.
- Opening and live reload edge cases (#41): while the document's folder is missing, the
  watcher sits on the nearest existing ancestor and follows the path back down; extensionless
  files that sniff as UTF-8 text open as plain text (`DocumentController.canOpen(_:)`, the one
  rule for the Open panel and drops). Peep still declares only Markdown (`Alternate`) and plain
  text (`None`), never `public.data`.
- Copy Link and find (#42): Copy Link never copies a `peep-doc:` URL (`CopyableLink`); the find
  bar shares the system find pasteboard; Jump to Selection (Cmd-J).
- No per-file zoom (#43): it would make Cmd +/- mean "this file" or "every file" depending on
  history; pinch already covers a one-off. (#47 makes zoom per window, not per file.) The outline gained Expand/Collapse All and a
  per-window, restored width.
- Missing custom theme fallback (#45): a window whose custom theme is deleted, broken, or not
  loaded yet shows Settings' default theme, and GitHub (the registry's default) only when that
  default is missing too; the window keeps its pick and shows it again when the file returns.
- Custom themes without `extends` (#45): unchanged, they start from the base layer only, with no
  highlight.js token colors; a theme written from scratch styles code itself (the guide and its
  example show how).

**After the close-out** (found while testing the milestone PR, #46, and merged with it):

- Appearance override: Settings > General and View > Appearance pick System, Light, or Dark
  for the whole app (`NSApp.appearance`); printing stays light.
- The toolbar's theme menu was dropped (a pull-down toolbar menu hid its first item, GitHub);
  View > Theme is the one picker.
- Dragging a link out of the page, Share on a link, and Copy Image no longer expose `peep-doc:`
  URLs (`PasteboardLinkRewriter` in PeepCore). Copy Image of a local image copies the file's
  bytes plus a PNG, and works for SVG.
- `docs/github-soft-dark.css`: an `extends: github` example theme (github.com's "Soft dark",
  Primer `dark_dimmed`), checked by `ThemeGuideTests`.

**Performance (#40):** cold open to first paint, as in #27 (process start to two animation
frames after the first page load finished, Release, file as an argument, outline hidden),
MacBook Air (Apple silicon), macOS 27.2, with `scripts/measure-cold-open`. Before and after
were launched interleaved in one sitting (median of 12 launches; 6-10 for the large files),
and the floor with them. The machine was shared with parallel builds (load average 5-9), so
absolute numbers run higher than on an idle machine (#27 measured an idle 372 ms for the
README); compare within a column set, not with #27.

| Document | Size | Before #40 | After #40 | Floor (bare `WKWebView`) |
| -------- | ---- | ---------- | --------- | ------------------------ |
| peep README | 1.7 KB | 398 ms | 341 ms | 348 ms |
| `bat` README (corpus) | 34 KB | 415 ms | 363 ms | 376 ms |
| Synthetic | 1 MB | 645 ms | 646 ms | |
| Synthetic | 5 MB | 1945 ms | 1921 ms | |

The gain varies with how long WebKit takes to start its content process: 13-78 ms for the
README across runs. The bare app's numbers include no menus, toolbar, sidebar, or SwiftUI;
Peep's come within 0-50 ms of it (another sitting: 338 ms vs 287 ms), because WebKit, not Peep,
is most of the critical path.

**Crash and hang pass (#45):** `AppTests` (289 tests, including the stress suite, extended with
theme switches racing rapid live reloads and a custom themes folder edited, broken, deleted, and
refilled while windows open and close) and `AppUITests` (33 tests, restoration included) pass
under Address Sanitizer and Thread Sanitizer in Debug, with no sanitizer reports. The Thread
Performance Checker flagged one priority inversion in Peep's code: the YAML frontmatter parser's
large-stack thread ran at default QoS while a user-initiated render waited for it; it now runs
at the caller's QoS, and a TSan re-run is clean. The UI runs' remaining runtime warnings come
from the XCUITest runner ("should not be called on the main thread", one per test; a QoS
warning marked `[Internal]` in the pasteboard tests), not the app. Hosted tests no longer leave
a `UserDefaults` plist per test in `~/Library/Preferences` (`ThrowawayDefaults`).

**Performance (#45):** the #40 harness on the finished milestone (`scripts/measure-cold-open
-f`, Release, MacBook Air, macOS 27.2, outline hidden, load average 5-10 from background
system work). The milestone build and the integration branch before #45 were launched
interleaved, with the floor, in one sitting: three rounds of 4 launches each (3 for the large
files), the median of the rounds' medians. A separate non-interleaved run of the milestone (12
launches, 8 for the large files) is in brackets.

| Document | Size | M3 (before #45) | M3 | Floor (bare `WKWebView`) | M3 minus floor |
| -------- | ---- | --------------- | -- | ------------------------ | -------------- |
| peep README | 1.9 KB | 333 ms | 336 ms (344) | 305 ms (300) | +31 ms (+44) |
| `bat` README (corpus) | 34 KB | 360 ms | 360 ms (389) | 328 ms (324) | +32 ms (+65) |
| Synthetic | 1 MB | 674 ms | 658 ms (682) | | |
| Synthetic | 5 MB | 2092 ms | 2069 ms (2146) | | |

Peep stays within the agreed 0-50 ms of the floor in the interleaved run (the separate run's
`bat` gap, 65 ms, came with load rising to 10). The 1 MB and 5 MB numbers match the build
before #45 in the same sitting; they run about 10% above #40's table, which was measured under
lighter load. The outline's first fill (about 20 ms on the main thread when a 5 MB render lands
with the sidebar shown) is still there; deferred, below.

**Deferred from M3** (from the issue handoffs; none blocks 1.0 on its own):

- Themes: keyboard shortcuts for themes and content width presets; keeping a broken custom
  theme's last good version while the file is broken; per-file symlinks in the Themes folder
  (a symlinked folder works); `os.Logger` instead of `NSLog` for theme failures; Copy as HTML
  with theme CSS (would revisit #38's "unaffected"); stripping unused vendored GitHub CSS
  (`.pl-*`, `.csv-data`, `g-emoji`); narrow-window padding for GitHub.
- Theme guide: screenshots (its paths were renamed with the app at the name gate); `@font-face
  { src: local(…) }` is neither rejected nor tested; `ThemeBase`'s comment says pages break
  around code, but only rows, images, and placeholders have `break-inside: avoid`.
- Print: a print-panel "Print backgrounds" option; no UI test drives the print panel (PDF output
  is checked by hosted tests); remote `https:` `<picture>` sources at print time are untested.
- Visual regression: no zoom/width variants, outline sidebar, or custom themes in the
  snapshots; each re-record adds about 2 MB per OS to history (Git LFS if themes churn); a
  macos-26 runner image update can require re-recording from CI's artifact.
- Settings: remembering the remote-image opt-in per file (decided against for now, #36); no
  Settings UI for restoration or for resetting the default viewer offer; no UI test for the
  Settings window's position; no manual VoiceOver pass.
- Performance: ~~the outline's first fill (about 20 ms on main for a 5 MB document with the
  sidebar shown; options: fill after the first load, or lazily while collapsed); no progress
  indicator for long first renders (about 0.4 s of an empty window at 5 MB)~~ done in M4
  (#58); no performance check in CI (needs a GUI session and Release; CI timing is too noisy); the prewarmed web
  view lingers if no document window ever opens.
- Opening and links: the find pasteboard isn't re-read on app
  activation while the bar is open; dropping an extensionless file from Finder and `peep
  CHANGELOG` are manual checks only; the Open panel sniffs every extensionless file it lists
  (fine locally, maybe slow on a large network folder); while a document's folder is missing,
  the watcher may sit on a busy ancestor such as `~`.
- Outline: the sidebar width is per window; new windows don't inherit the last width.

**Exit criteria:** switching themes is instant; a custom CSS file appears and updates without
restart; bundled themes pass a visual regression check. ✅ (automated checks; the manual
checklist is in the milestone PR)

## M4: Flavors and preprocessors

**Status:** Done (2026-11-10, #60).

Control how source becomes Markdown.

- Flavor presets: CommonMark (strict), GFM (default), plus room for others; each a defined set of
  parser options and AST transforms (#51)
- Built-in preprocessors: wiki links `[[Page]]` (#53); frontmatter is extracted in every flavor
  and shown hidden or as a table. Include/transclusion: not done (deferred, below)
- Custom preprocessor: user-configured executable, document on stdin, Markdown on stdout,
  timeout and size limits, explicit opt-in with a clear warning (#56, #57)
- Per-document overrides via frontmatter (`peep: { flavor: commonmark, theme: github }`, #54).
  The window's pick beats the document's theme, which beats Settings' default; restoration keeps
  only the pick
- Frontmatter display as a table in Settings > Markdown (#55); `docs/THEMES.md` documents
  `table.frontmatter`/`pre.frontmatter`
- GitHub alerts (`> [!NOTE]`) in the GFM flavor, styled in every bundled theme (#52)
- Settings UI for flavors and preprocessors: Settings > Markdown (#55, #57)
- Feedback for slow renders: a delayed progress indicator, and the outline filled after first
  paint (#58)
- ~~Carried over from M3: per-window zoom and content width, with Settings setting the default
  for new windows (#47). Restoration keeps each window's values.~~ Done (#47, ahead of M4).

**Exit criteria:** each flavor has its own test corpus; a misbehaving script (hang, crash,
huge output) cannot hang or crash the app. ✅ (`Fixtures/flavors/<id>/`, enforced by
`FlavorCorpusTests`; `StressTests+Preprocessor` and `+Markdown`, also under ASan and TSan; the
manual checklist is in the milestone PR)

**Decisions:**

- Flavor vs feature split (#51): a `Flavor` owns syntax only, its cmark-gfm extensions and the
  AST transforms it always runs. Bundled: `gfm` (default; every extension, emoji shortcodes,
  alerts from #52) and `commonmark` (none). Emoji shortcodes are GFM-only. Heading anchors,
  highlighting, source lines, sanitizing, remote images, `linkRoot`, markup style, and
  frontmatter detection and display stay `RenderOptions` features independent of the flavor;
  CommonMark keeps frontmatter detection (metadata, not syntax). Opt-in built-in preprocessors
  (wiki links, #53) are `RenderOptions.builtInPreprocessors`, also independent of the flavor.
  `FlavorRegistry` resolves ids; unknown ids are GFM. See VISION.
- Render pipeline (#51): custom preprocessor (whole file, opt-in) → frontmatter extraction →
  flavor resolution (frontmatter `peep.flavor`, #54) → parse → AST transforms → HTML, in
  `HTMLRenderer.render(_:)`. Built-in preprocessors are AST transforms over text nodes, not text
  passes, so code and raw HTML are never rewritten. Transforms (`MarkdownTransform`) run in one
  fixed order, whatever enabled them: alerts, wiki links, emoji. After a custom preprocessor,
  `data-source-line` refers to the preprocessor's output. See VISION.
- GitHub alerts (#52): an AST transform in the GFM flavor (`GitHubAlerts`, first in the
  transform order) matching github.com's rules, each verified with `gh api markdown` and kept
  as `Fixtures/github/alerts.md`: top-level block quotes only (no nesting, none in lists or
  footnotes), the case-insensitive marker alone on the first line of a first paragraph, and a
  body required (a lone marker stays a block quote). GitHub's markup and Octicon SVGs are
  renderer constants (no CSP change); the alert `div` carries `data-source-line`, the title
  doesn't and isn't a heading (not in the outline). Themes: GitHub's vendored rules; Document
  (shaded callout, unshaded on paper) and Serif (rule and small-caps title); `ThemeBase` gives
  a theme without `extends` a left rule and title layout, and keeps alerts whole on paper where
  they fit. Known divergence: a quote between raw HTML tags (`<details>` … `</details>` in
  separate HTML blocks) is top level in Peep's tree, so it becomes an alert; github.com keeps it
  a block quote.
- Settings > Markdown (#55): default flavor, frontmatter display (hidden or a table), and
  opt-in built-in preprocessors in one `MarkdownSettings` store; changes re-render open
  documents in place (the live reload swap, reading position kept), and frontmatter
  `peep.flavor` (#54) still wins. No per-window flavor menu: flavor belongs to the file
  (frontmatter) or the reader's one default, and is per document, not per window. The bundled
  themes already style `table.frontmatter` and `pre.frontmatter` (light, dark, print); no theme
  CSS or snapshot change. See VISION.
- Wiki links (#53): an opt-in built-in preprocessor (Settings > Markdown, or `peep.wikilinks`,
  which beats Settings both ways), independent of the flavor. `[[Page]]`, `[[Page|label]]`
  (label second, unlike Gollum), `[[Page#Heading]]`, `[[#Heading]]`; plain text only, brackets
  written as is (`\[[` stays literal, checked against the source line). GitHub wiki naming
  (`Page Name` → `Page-Name.md`, case-insensitive, space = hyphen, Markdown extensions only).
  Searched in the document's folder, then the allowed root breadth first, never outside it,
  skipping hidden entries and symbolic links, capped at 10,000 entries. PeepCore takes an
  injected `WikiLinkResolver` (`FolderWikiLinkResolver` over an injected folder reader; the app
  reads the disk). Found: a relative, percent-encoded `a.wikilink` through `LinkPolicy`;
  missing: `a.wikilink.wikilink-missing` with no `href` (dashed underline from the base
  layer, no theme CSS or snapshot change). Resolved at render time only; `peep --html` has no
  resolver yet (M5). Fixtures `Fixtures/flavors/*/wiki-links*.md`. See VISION.
- Per-flavor corpus (#51): `Tests/PeepCoreTests/Fixtures/flavors/<id>/` (`.md` plus recorded
  `.html`, `PEEP_RECORD_SNAPSHOTS=1`), one folder per registered flavor; GFM is also checked
  against github.com by the README corpus.
- Per-document overrides (#54): `DocumentOverrides` (PeepCore) reads `flavor`, `theme`, and
  `wikilinks` from the YAML frontmatter's `peep:` mapping; other keys and wrong types are
  ignored and reported in `RenderedDocument.overrides`. Presentation only: frontmatter can't
  enable the custom preprocessor, turn off sanitizing, allow remote images, or change any other
  setting (`RenderOptions.applying(_:)` touches only the flavor; tests prove each). The flavor
  beats `RenderOptions.flavor` before parsing (`peep --html` too); an unknown one keeps the
  reader's default. Theme precedence: the window's View > Theme pick, then the document's
  theme, then Settings' default; same fallback as a pick. Restoration saves only the pick. A
  live reload that changes `peep.theme` swaps the theme in place. View > Theme checks the shown
  theme and has "Document's Theme" to drop the pick. TOML `[peep]` is unsupported (documented,
  reported as ignored); no TOML parser. `peep --html` uses a bundled frontmatter theme. See
  VISION.
- Custom preprocessor runner (#56): `CustomPreprocessor` in `PeepCore`. The document's path is
  passed in `PEEP_DOCUMENT_PATH`, never as an argument. The working directory is the document's
  folder (`/` without a file). The environment is fixed (`PATH` with Homebrew's folders,
  `HOME`, `TMPDIR`, `LANG`). The executable is an absolute path, never looked up on `PATH`,
  and it is validated when configured and again before each run (links followed only for
  the check). Limits: 5 s, 10 MB in, 10 MB out, a 64 KB stderr tail, and `SIGTERM` to the
  process group, then `SIGKILL` 0.5 s later. Its stage 1 adapter is `for(documentURL:)`
  (`SourcePreprocessor`). Fixture scripts cover each misbehavior, and the tests check that no
  process or descriptor leaks. See VISION's security model.
- Custom preprocessor in the app (#57): off by default, turned on only in Settings > Markdown
  after a warning, with the program chosen in an Open panel and arguments as a list
  (`CustomPreprocessorSettings`, `MarkdownPreferences.customPreprocessor`). It runs on every
  document the app opens (no extension filter). A failure renders the document without it plus a
  bar with the reason and a Show Details stderr disclosure (no alert, no error page). Settings
  shows the session's last run instead of a "Test on…" button. Live reload reruns it; newer
  renders, `setContent`, and closing cancel the run in flight; Settings changes re-render open
  documents and restart outdated runs. Frontmatter can't enable it. `StressTests+Preprocessor`
  covers hang, crash, flood, fork, reload storms, and closing mid-run. See VISION.
- Feedback for slow renders (#58): a wait over 300 ms (`RenderProgress.defaultDelay`, injected
  in tests) shows an indeterminate indicator; shorter ones never flash it. Before the first page
  loads it sits in the middle of the blank page on the theme's background (drawn in the
  appearance that contrasts with it) and goes when the page loads. Re-renders (live reload,
  Settings changes, a slow preprocessor) keep the old page, never blanking it, and show a small
  indicator in the top corner: decided yes, but subtle (a material circle, no clicks taken),
  since a reload of a large file or a slow script otherwise looks like nothing happened. The
  outline's first fill runs after the first page paints (two animation frames, or 100 ms when
  WebKit isn't drawing the window), and the sidebar is blank rather than "No Headings" until
  then. `MarkdownDocument.isRendering` covers both a render and a live reload in flight. See
  VISION.

**Performance (#58):** the #45 harness (`scripts/measure-cold-open -f`, Release, MacBook Air,
macOS 27.2), before (#57's merge, 2c6c400) and after #58 launched interleaved with the floor in
one sitting: three rounds of 4 launches (3 for the large files), the median of the rounds'
medians. The synthetic documents are `FirstRenderTests.largeSource(bytes:)`, as in #40 and #45.
**The machine wasn't idle:** no other agents ran, but load averaged 4-9 (a system daemon,
`duetexpertd`, held one core throughout, and load rose in the third round), so compare within
this table, not with #45's.

| Document | Size | Before #58 | After #58 | Floor (bare `WKWebView`) | After minus floor |
| -------- | ---- | ---------- | --------- | ------------------------ | ----------------- |
| peep README | 4.4 KB | 336 ms | 335 ms | 298 ms | +37 ms |
| `bat` README (corpus) | 34 KB | 358 ms | 357 ms | 320 ms | +37 ms |
| Synthetic | 1 MB | 654 ms | 643 ms | | |
| Synthetic | 5 MB | 2126 ms | 2200 ms | | |
| Synthetic, outline shown | 5 MB | 2150 ms | 2162 ms | | |

README-sized opens are unchanged and within the agreed 0-50 ms of the floor. At 5 MB the rounds
spread by 100-450 ms under this load, so the cold-open harness can't resolve the outline's
~20 ms either way; the hosted measurement does (`FirstRenderTests`, Debug, same sitting, two
runs each): with the outline shown, the longest main-thread busy stretch between the render
landing and the page load was 19.1-19.4 ms before and 1.5 ms after (the fill now comes after
the first paint), the same as with the outline hidden. The test's bound with the outline shown
dropped from 50 ms to 17 ms. Re-measure 1 MB and 5 MB on a quieter machine at the close-out if
absolute numbers are wanted.

**Decisions at the close-out (#59):**

- UI tests hold up renders with a Debug-only launch hook, `-PeepUITestRenderDelay <seconds>`
  (`UITestHooks.renderDelay`, compiled out of Release, at most 30 s, cancelled with the
  render), instead of a 4 s preprocessor script, which a slow CI launch could outlast.
- When `posix_spawn` refuses a preprocessor that passed the executable check (`EPERM` or
  `EACCES`), the bar's reason adds a likely cause without claiming it: the file may be
  quarantined (downloaded, or saved by a sandboxed app), with `xattr -d com.apple.quarantine`
  and System Settings > Privacy & Security to try. Seen with scripts the sandboxed UI test
  runner writes; a quarantined script launched from a terminal ran, so the cause isn't
  confirmed for downloads.
- The GitHub repository became public (it was to stay private until 1.0); the name gate renamed it
  rather than publishing it.

**Crash and hang pass (#59):** `AppTests` (365 tests, including the stress suite) and
`AppUITests` (46 tests, restoration included, run separately with
`TEST_RUNNER_PEEP_UI_TEST_RESTORATION=1`) pass under Address Sanitizer and Thread Sanitizer in
Debug, with no sanitizer reports and no runtime issues from Peep's code. The stress suite gained
`StressTests+Markdown`:

- Settings > Markdown (flavor, frontmatter table, wiki links) changing during first renders
  (a 1 MB document among them) and rapid live reloads;
- frontmatter `peep.theme` and `peep.flavor` changing under rapid live reloads, with the reader
  picking and dropping a theme and changing both defaults meanwhile;
- one preprocessor script that hangs, crashes, floods stdout, or fails depending on the file,
  switched by live reload, with its arguments changing mid-run.

Each ends on the newest content and settings, with no process left. The sanitizer and stress
runs found no app bug; macOS 26 CI later exposed one (see "After the close-out").

The macOS 26 CI run on the integration branch (5ae19c2) failed two tests, both test problems:

- `StressTests+Preprocessor`: the main-thread heartbeat ran while twelve windows started
  their web content processes. On the runner that stalled the main thread for 3.8 s, with
  0.27 s of CPU time, before any script result landed; even the crashing script's result
  took 4.8 s, so the whole VM was starved. The runner's cancel, validation, and spawn code
  never runs on the main thread. The misbehaving scripts are now timed on a live reload once
  the windows are up. The close test times each `close()` (a close that waited for a
  TERM-ignoring script would take the 0.5 s grace period). The bounds are unchanged.
- `ThemesUITests.testFrontmatterThemeOpensInThatTheme`: "Document's Theme (Serif)" has that
  title only while the menu is open (validation sets it; its accessibility title is
  "Document's Theme"), so XCUITest's lookup after the click failed once the menu had closed.
  The test chooses it by identifier.

ASan reproduced the first failure locally (the close test's heartbeat, 1 of 365 tests) before
the fix; the stress suite then passed three runs in a row without sanitizers.

**After the close-out (macOS 26 CI, before #60 merged):**

- **Lost theme swap, a real bug** (from #34, exposed by M4's extra theme switches on starved
  runners). Switching A to B and back to A while B's swap was in flight left the page on B for
  good: `WebViewCoordinator.swapThemeIfNeeded()` compared against `loadedTheme`, which only
  caught up when the swap script answered. Swaps now run one at a time and re-check after each,
  and `pageGeneration` stops a swap that finishes after a new load from claiming that page. A
  `ThemePickerTests` regression test failed every time on the old code with no CPU load.
- **Main-thread timing bounds are report-only on CI** (`expectTiming`,
  `AppTests/Support/MainThreadTiming.swift`). CI's app-test step sets
  `TEST_RUNNER_PEEP_TIMING_REPORT_ONLY`; `xcodebuild` forwards only `TEST_RUNNER_` variables to
  the test process, never `CI`. The runners showed 0.26-0.67 s main-thread gaps with almost no
  CPU used, and 18-27 ms busy times on code that measures 1.3-1.5 ms on a real Mac with every
  core loaded. A throwaway experiment (#61) ruled out #58's progress indicator. On CI a miss is
  logged as a known issue; locally the bounds stay strict.
- **Test races fixed:** a settings test that checked once instead of waiting for the end state,
  the preprocessor cancellation margin, and an alert-button query that matched CI's Touch Bar
  copy (query alert and sheet buttons inside their window).

When a correctness check (not a timing bound) times out on CI, suspect a race before raising
the timeout, and reproduce locally with `yes` loading every core.

**Performance (#59):** no re-run for the table: the machine was still busy at
the close-out (load 5-7, `duetexpertd` holding a core again, plus Spotlight indexing the build
folders), so #58's table above stands for M4. Nothing in #59 changes a Release code path, apart
from one error message and a Debug-only hook that compiles to `nil`. A non-interleaved spot
check of the finished milestone (10 launches each, load 5-6) gave the README (4.9 KB) 354 ms
against a 303 ms floor (+50) and `bat` 392 ms against 336 ms (+57). That's in line with M3's
non-interleaved runs (+44, +65) rather than a regression; interleaved runs on a quiet machine
are the ones to compare.

**Deferred from M4** (from the issue handoffs; none blocks 1.0 on its own):

- Pipeline and flavors: include/transclusion (no design yet); `RenderedDocument` doesn't report
  the flavor a document actually rendered with, so the UI can't say "this document overrides
  to CommonMark"; no UI for `RenderedDocument.overrides.ignored` (frontmatter keys Peep ignored
  and why).
- Alerts: a quote between raw HTML blocks (`<details>` … `</details>`) becomes an alert where
  github.com keeps a block quote (known divergence, #52); titles are always English, as on
  GitHub.
- Wiki links: `peep --html` has no resolver, so page links render as missing there (M5); a link
  to a heading goes to the first heading with that text (slugs aren't de-duplicated against the
  target); no tooltip on missing links; a `.markdown` and `.md` tie in one folder goes to name
  order; targets appearing or disappearing don't re-render (the next render picks them up).
- Custom preprocessor: non-UTF-8 sources can't be converted (the file must decode as UTF-8
  first); the runner is not a sandbox (`setsid` escapes the group); the quarantine hint is
  unconfirmed for downloaded scripts (no reproduction outside the UI test runner).
- Slow renders: the corner indicator hides when the render lands, not when the in-place swap
  finishes (a few hundred ms more at 5 MB); no indicator while a reload only reads the file.
- Settings > Markdown: the flavor picker's note doesn't mention that frontmatter `peep.flavor`
  wins.

## M5: CLI

**Status:** Done (2026-11-11; the milestone PR merges after review).

Make the terminal workflow excellent.

- `peep FILE...` opens files in the app, launching it if needed, through Launch Services with a
  standard Open Documents Apple Event, as Finder does (#67); `--theme` becomes the windows'
  View > Theme pick
- `cmd | peep` opens standard input in an untitled window, through a private handoff file the
  app deletes as soon as it has read it (#68)
- `--html`, `--fragment`, and `-o`/`--output` (#63; `--standalone` was dropped, since pages are
  already standalone); `--theme` and `--flavor`, custom themes included, plus `--list-themes`
  and `--list-flavors` (#64)
- Flags for the render options: frontmatter table, wiki links, source lines, highlighting,
  heading anchors, remote image placeholders (#65); nothing turns sanitizing off.
  `--preprocessor PATH` runs a custom preprocessor only when asked (#66)
- `--wait` blocks until the windows it opened close, or the app quits (#69)
- Install Command Line Tool in the App menu (`~/.local/bin` or `/usr/local/bin`, with Repair
  and Uninstall), which links the man page too (#70, #71)
- Shell completions (zsh, bash, fish) and a man page, generated from the command (#71)
- CLI integration tests: `PeepCLITests` (in process and with the built binary) under
  `make test-core`, and UI tests that run the CLI (`CommandLineUITests`,
  `StandardInputUITests`, `WaitUITests`, `CommandLineToolUITests`)

**Exit criteria:** every example in the README works; CLI tests run in CI. ✅
(`ReadmeExampleTests` runs every `peep` command in the README's `sh` blocks under
`make test-core`, which CI runs, #72)

**Decisions** (details in [VISION](VISION.md#architecture-overview), "CLI"):

- CLI foundation (#63): the command is the `PeepCLIKit` library with one option group file per
  concern and a thin `CLI/Main`; `PeepCLITests` runs under `make test-core` (in-process through
  `PeepCommand.execute(in:)`, plus end-to-end runs of the built binary). `--standalone` is
  dropped (`--html` pages are already standalone); `--fragment` prints body HTML only;
  `-o`/`--output` writes atomically and never over an input. Several inputs share an output
  only as fragments. Exit statuses follow `sysexits(3)` (64, 65, 66, 69, 73, 74). With no FILE
  and a terminal on standard input, Peep prints usage; `-` reads standard input explicitly.
- Theme and flavor (#64): `--theme`/`--flavor` beat the document's `peep:` frontmatter, which
  beats the default (PeepCore `RenderOptions.pinnedOverrides`; `RenderedDocument.flavor` reports
  the flavor used). `--theme` accepts `custom:<file name>` from the Themes folder
  (`PEEP_THEMES_FOLDER` overrides it), and a custom frontmatter theme now loads in `--html` too.
  Unknown flag ids are usage errors; a missing or invalid custom theme exits 66 or 65 with the
  reason. `--list-themes` and `--list-flavors` added.
- Render flags (#65): `--frontmatter hidden|table`, `--wiki-links`/`--no-wiki-links` (beats
  `peep.wikilinks`), `--source-lines`, `--no-highlight`, `--no-heading-anchors`,
  `--block-remote-images`; HTML output only (usage error otherwise). No `--no-sanitize`, and the
  CLI doesn't read Settings > Markdown (both in VISION's security model). File inputs get the
  app's `linkRoot` and a `FolderWikiLinkResolver` (`FileSystemFolderReader` moved to PeepCore);
  stdin gets neither. Wiki links stay `.md` in `--output`. Ignored `peep:` keys are warnings on
  standard error; `--verbose` adds the flavor and wiki link setting used.
- Custom preprocessor (#66): `--preprocessor PATH` plus repeatable `--preprocessor-arg`, HTML
  output only; the app's setting is never read. Same runner and limits as the app; stdin runs
  in `/`. Failure exits 70 with the reason and stderr tail, no HTML, no fallback flag. Ctrl-C
  (also `SIGTERM`, `SIGHUP`) cancels the run, stops its process group, then ends Peep with the
  signal (end-to-end test with the built binary).
- `peep FILE` (#67): the CLI gives Launch Services a standard Open Documents Apple Event with
  Peep's own parameters (`peepT` theme id; `AppOpenEvent` in PeepCore), so opening is Finder's
  path (no Automation prompt). It opens the app that contains it (a dev build opens itself;
  outside a bundle, the app with Peep's bundle id); with another copy running it launches or
  messages its own copy (`Peep/odoc`, since AppKit drops parameters from a directly sent
  `odoc`). Paths and `--theme` are checked before anything opens (66, 64/66/65). `--theme`
  becomes the windows' View > Theme pick (an open window switches); `--flavor` without HTML
  output is a usage error. Parameters are presentation-only and validated in the app as
  untrusted. #69 added `peepW` to the same event; `peepI`, reserved for #68, wasn't needed.
- `cmd | peep` (#68): standard input goes to the app as a private handoff file
  (`$TMPDIR/peep-stdin.XXXXXXXX/stdin.md`, 0700/0600, `StandardInputHandoff` in PeepCore), one
  of the Open Documents event's files; `DocumentController` recognizes it by its shape (no
  `peepI` parameter: AppKit drops parameters on some launch paths, and any sender could set
  one), deletes it once read, and shows an untitled "Standard Input" window (titled from the document when it can be) that live reload,
  Open Recent, and restoration skip. The app deletes only files it verifies are handoffs
  (shape, owner, permissions, one link, no symbolic links); anything else opens as a file. At
  most 10 MB; empty (66), larger (65), and non-UTF-8 (65) input open nothing. No allowed root
  (relative images don't load), no wiki link resolver, preprocessor in `/`. No streaming
  (deferred). `-` with files opens the files, then standard input. `cmd | peep --wait` waits for
  the standard input window.
- `--wait` (#69): a random token per invocation (`peepW`); the app posts the Darwin notification
  `now.peep.Peep.windowsClosed.<token>` once every window that event opened or brought
  forward (an already-open file's counts) has closed, or on quit; the CLI also watches the
  app's process, so a crash or force quit ends the wait (exit 0). Ctrl-C ends Peep (130) and
  leaves the windows open. A forged notification can only end a wait early; the app accepts
  only a UUID token. `--wait` with HTML output is a usage error. The README's git example
  pipes into it (`git show HEAD:README.md | peep --wait`, #68).
- Install Command Line Tool (#70): one App menu item whose title follows the state (Install,
  Repair for a link left by a moved or renamed app, Uninstall for this copy's link), read from
  disk each time the menu opens; nothing is repaired without asking. Both `~/.local/bin` (no
  password) and `/usr/local/bin` (administrator password via a constant AppleScript `do shell
  script`, paths passed as parameters) are offered; the default is the first that needs no
  password and is on the login shell's `PATH`, else `/usr/local/bin`, else the folder of an
  existing link. After installing somewhere that may not be on `PATH`, the alert shows the
  `export PATH=…` line. Only our symlink (into a Peep.app with our bundle id, or a gone one) is
  ever replaced or removed; it is created by atomic rename. With several copies of Peep, the
  alert names the one the link will use. #71 added the man page as a second
  `CommandLineToolInstaller.Item` (completions aren't installed). See VISION's security model.
- Completions and man page (#71): generated from the ArgumentParser command, not committed
  (`make cli-docs` into `build/cli-docs`; `make test-core` and `make build` run it). zsh, bash,
  and fish scripts from ArgumentParser; `--theme` completes `--list-themes`' ids when Tab is
  pressed. The man page is the `generate-manual` plugin's, finished with hand-written sections
  built from code (`ManualPage`: EXIT STATUS from `ExitStatus.entries`, EXAMPLES from
  `HelpText`, FILES, ENVIRONMENT, SECURITY CONSIDERATIONS). A test checks every option from
  `--experimental-dump-help` is in the page and the scripts. The app bundles them in
  `Contents/Resources/{man/man1,completions}` (paths for the M6 cask); Install Command Line
  Tool also links the man page into `share/man/man1` beside the command (one password prompt);
  completions are documented, not installed.

**Decisions at the close-out (#72):**

- The README's examples are tests (`ReadmeExampleTests`; the reader is
  `Tests/PeepCLITests/Support/ReadmeExamples.swift`). A small shell reader (words, quotes, comments, `|`, `>`, `&&`) takes every `peep` command
  out of the `sh` blocks; one it can't read fails the test instead of being skipped. Examples
  that print or write HTML run the built binary in a temp folder holding the files they name
  (`README.md` is the real README). Examples that open the app run in process with the
  recording opener and must send what they say: the files, standard input from a pipe,
  `--theme`, `--wait`. The completion block's script names are checked against
  `make cli-docs`' output. Prose mentions in inline code aren't run. The README gained a block
  of window examples (files, `--theme`, `git show … | peep --wait`).
- The CLI-driven stress cases (`StressTests+CommandLine`) are app-side: open events go
  through `DocumentOpener` as `AppDelegate` sends them, so they run in the hosted suite and
  under the sanitizers without launching copies of the app or depending on Launch Services
  timing. They cover 24 `peep FILE` events at once (files shared between events, standard
  input in every third: each file opens once, every handoff is deleted), `--wait` tokens when
  the app quits mid-open (each notified exactly once, including events that finish opening
  after the quit), the largest standard input the CLI sends (10 MB renders, with the main
  thread busy at most ~80 ms; one byte more is refused and deleted), and `--theme` re-sent
  while windows' first renders are in flight (each ends on the last theme, in the window and
  the page). No app bug turned up.
- Events sent that fast make about twenty windows in one turn of the main queue, which kept
  the main thread busy about 0.55 s in Debug, presumably window and web view setup, as when
  Finder opens that many files at once; the CLI path adds nothing on the main thread but
  reading the handoff. That test has no main-thread bound; the 10 MB one has (500 ms).
- **`--theme` and `--wait` were lost on every Launch Services path** (found by CI's UI tests;
  fixed before the merge). AppKit opens an Open Documents event's files itself for a
  document-based app (`_handleAEOpenDocumentsForURLs:` → `NSDocumentController`) and never
  calls the delegate's `application(_:open:)`, so #67's design, checked with a probe app that
  had no document types, held only for the direct `Peep/odoc` path that local UI tests took
  while an installed Peep was running. A Carbon handler for `aevt/odoc`
  (`OpenDocumentsEventTap`, installed in `applicationWillFinishLaunching`) now records each
  event's parameters by file (`OpenDocumentsEventLog`: taken once per file, 30 s, at most 32)
  and passes the event on unchanged; `DocumentController.openDocument(…display: true…)` hands
  a file with Peep parameters to `DocumentOpener.openForOpenDocumentsEvent`, which also covers
  files AppKit defers until an earlier open finishes (no current event by then).
  `application(_:open:)` is gone. The CLI sends the direct event with `.noReply`: a modal
  alert in the app (the first-run default viewer offer) holds up Apple Event handling, and
  waiting for a reply made the CLI exit 69 for files the app then opened.
- **The preprocessor `SIGINT` test failed on CI** (fixed before the merge). The test's polling
  task starved on the cooperative pool and signalled Peep after it had already timed out; it
  now waits and signals from a dedicated thread, and the run gets a Debug-only longer timeout
  (`PEEP_TEST_PREPROCESSOR_TIMEOUT`). Two product fixes came with it: `InterruptCancellation`
  records the signal in its `sigaction` handler (and the dispatch source), so a signal landing
  as a run ends isn't lost, and the re-raise is a process-directed `kill` plus a wait, because
  the async command runs on workqueue threads, which Darwin never delivers signals to (about 1
  run in 4 printed "interrupted" before dying of the signal).
- **Closed windows leaked their document, web view, and web content process** (found by the
  stress suite on CI's starved runner; fixed before the merge). **This predates M5 and may
  have affected every build before the fix:** AppKit can keep a closed window alive for minutes, and
  its content held the document and the web view, so each window a reader closed kept a web
  content process until AppKit let the window go. `DocumentWindowController` now drops its
  `contentViewController` on close, and the outline's wait for two animation frames no longer
  retains the web view (a window that isn't drawing runs no frames, so that wait never ended).
  `StressTests` checks a closed document is freed.
- Core render timing bounds (`Tests/PeepCoreTests/RenderTiming.swift`) are report-only on CI
  (`PEEP_TIMING_REPORT_ONLY` in the core step), like the app's main-thread bounds since M4.

**Crash and hang pass (#72):** on feature/m5-cli with every fix above (52d909e), Debug,
team-signed, macOS 27.2, `AppUITests` with `TEST_RUNNER_PEEP_UI_TEST_RESTORATION=1`:

| Suite | Address Sanitizer | Thread Sanitizer |
| ----- | ----------------- | ---------------- |
| `AppTests` (431 tests, stress suite included) | passed | passed |
| `AppUITests` (57 tests) | passed | 56 passed, 1 failed (below) |

No sanitizer reported anything. The one failure,
`CommandLineUITests.testThemeFlagBecomesTheWindowsPick` ("no pick any more", after choosing
View > Theme > Document's Theme), failed under TSan in 8 of 9 runs (the whole suite, the class alone, and that test alone). It
is the UI test's reading, not the app: a probe in the app showed one `setTheme` from the
`--theme` open, one `clearThemePick` from the click, the page restyled, and every later menu
validation of Document's Theme returning disabled, while XCUITest went on reading the item as
enabled for 30 s of re-opened menus. Not fixed; the test passes under ASan, passed in the
bugfix's plain Debug runs, and passes on CI.

**Performance (#72):** Release, MacBook Air, macOS 27.2, 52d909e, one sitting; load 2.8-4.4
(no other agents; Spotlight finished indexing the sanitizer builds first).
`scripts/measure-cold-open -s -f -c -n 4 README.md` and then the 1 MB and 5 MB synthetic
documents (`FirstRenderTests.largeSource`, 3 launches each), three rounds interleaved; the
median of the rounds' medians. "Painted" is milliseconds from the process starting; "from the
command" is from running `open` or `peep` (Launch Services' part included).

| Document | Size | Painted | Floor (bare `WKWebView`) | Minus floor |
| -------- | ---- | ------- | ------------------------ | ----------- |
| peep README | 13.3 KB | 350 ms | 297 ms | +53 ms |
| Synthetic | 1 MB | 665 ms | | |
| Synthetic | 5 MB | 2118 ms | | |

| README by path | Painted | From the command |
| -------------- | ------- | ---------------- |
| `open -n -a Peep.app README.md` (Finder's path) | 363 ms | 408 ms |
| `peep README.md` (the CLI) | 344 ms | 387 ms |

- **`peep FILE` is as fast as Finder's path:** 21 ms quicker from the command in this sitting
  (#67 measured 4 ms slower), inside the rounds' spread (open 400-412 ms, Peep 379-393 ms), so
  the CLI's Apple Event costs nothing measurable.
- The README is three times the size it was at M4 (4.4 KB then), so +53 ms over the floor
  isn't comparable with M4's +37 ms; the rounds gave +31, +27, and +59 ms. Re-check the
  README against the 0-50 ms target on a quiet machine before 1.0.
- 1 MB and 5 MB are M4's 643 ms and 2200 ms within this machine's noise.

`peep --html`, the Release helper, median of 10 runs after a warm-up (wall clock, file cache
warm, `PEEP_THEMES_FOLDER` pointing nowhere):

| Command | Median |
| ------- | ------ |
| `peep --version` (process start) | 5.6 ms |
| `peep --html README.md` | 16.7 ms |
| `peep --html --no-highlight README.md` | 7.3 ms |
| `peep --html` 1 MB | 125 ms |
| `peep --html --no-highlight` 1 MB | 75 ms |
| `peep --html` 5 MB | 394 ms |
| `peep --html --no-highlight` 5 MB | 336 ms |

Starting the CLI costs about 6 ms. highlight.js in JavaScriptCore is most of a small page's
time (about 9 ms of the README's 17) and stays near 50-60 ms at
1 MB and 5 MB because of the 256 KB per-document highlighting budget.

**Deferred from M5** (from the issue handoffs; none blocks 1.0 on its own):

- Output: no `--output-dir` (#63); root-relative URLs in `--html FILE` become absolute paths
  of the reader's folders, with no flag to keep them as written (#65); wiki links stay `.md`
  in `--output` (#65).
- Opening: no `--background` (#67). Files sent while the app shows a modal alert (the
  first-run default viewer offer) open only once it closes; the CLI no longer waits for them.
- Testing: `CommandLineUITests.testThemeFlagBecomesTheWindowsPick` fails under the Thread
  Sanitizer only (XCUITest reads Document's Theme as enabled after the app disabled it; see
  the crash pass above). A UI test that drives the pure Launch Services path while an
  installed Peep runs isn't possible (Launch Services routes by bundle id); it runs locally only
  with the installed copy quit, and always on CI.
- Standard input: no streaming (`tail -f log.md | peep` never opens, #68); relative images in a
  standard input window show as broken images, not a placeholder (#68).
- Preprocessor: the CLI passes the script the decoded input re-encoded as UTF-8, not the
  file's raw bytes (differs only when a byte order mark was dropped; the app passes exact
  bytes, #66).
- Completions: in bash, `:` splits words, so `--theme custom:<Tab>` doesn't complete (complete
  from `cu<Tab>`, #71); interactive zsh completion was checked by reading the script, not by
  driving a shell (#71). The app doesn't install completions (documented, #71).
- Install Command Line Tool: the administrator path is tested without a real password (same
  handler and scripts minus the privilege clause); `PATH` entries set only in `.zshrc` aren't
  seen by the login-shell probe, so the alert words it as "may not be on your PATH" (#70).
- Small cleanups: the app's `DocumentWikiLinks` could use PeepCore's
  `FolderWikiLinkResolver.fileSystem(forDocumentAt:root:)` (#65).

## Gate: choose the name

Done. The working name `mdv` became **Peep**, with the site at [peep.now](https://peep.now)
(Cloudflare Workers). Bundle identifier, repository name, Sparkle feed URL, Homebrew cask, and
website all depend on the name, and changing them after release breaks updates, so everything
was renamed in one pass before M6:

- **Names:** the app is `Peep.app` (display name Peep, Xcode project `Peep.xcodeproj`, scheme
  `Peep`); the command is `peep` (`Peep.app/Contents/Helpers/peep`, Xcode target `peep-cli`,
  SwiftPM product `peep`); modules and types use the `Peep` prefix (`PeepCore`, `PeepCLIKit`,
  `PeepApp`, `PeepCommand`, `PeepInfo`, `PeepUITestApp`).
- **Identifiers:** bundle id base `now.peep.Peep` (the CLI is `.cli`, the exported UTI
  `.markdown`); the `--wait` notification `now.peep.Peep.windowsClosed.<token>`; Apple Event
  class `Peep` (`0x50656570`) with parameters `PepT` (theme) and `PepW` (wait).
- **Readers' files:** frontmatter `peep:`, custom theme header `/* peep-theme`, the Themes folder
  `~/Library/Application Support/Peep/Themes`, `PEEP_DOCUMENT_PATH` and `PEEP_THEMES_FOLDER`,
  cascade layers `peep-base`/`peep-theme`/`peep-user`, and the `peep-doc:` URL scheme.
- **Clean break:** nothing had shipped, so the old names aren't read as fallbacks: an `mdv:`
  frontmatter key is ignored like any other key, an `mdv-theme` header doesn't load, the old Themes
  folder and settings (keyed by the old bundle id) are left behind, and links made by the old
  Install Command Line Tool aren't recognized as the new installer's own.
- **Repository:** `itspriddle/mdv` became `itspriddle/peep` (GitHub redirects the old URL).
  Test-only variables are `PEEP_…` (`PEEP_RECORD_SNAPSHOTS`, `TEST_RUNNER_PEEP_…`, and so on).

## M6: Distribution and v0.1.0

Ship a first public release, v0.1.0.

- Developer ID signing and notarization in CI (secrets in GitHub Actions; signing identity never
  committed)
- DMG (or zip) packaging with app and CLI
- [Sparkle 2](https://sparkle-project.org): EdDSA signing keys, appcast hosted on
  [peep.now](https://peep.now) (Cloudflare Workers), update channel settings
- Tag-driven release workflow: build → sign → notarize → staple → publish GitHub Release → update
  appcast
- Version bumping keeps `MARKETING_VERSION` and `PeepInfo.version` in sync
- Homebrew cask
- Project site / landing page at [peep.now](https://peep.now) (Cloudflare Workers); CONTRIBUTING
  and issue templates
- Acknowledgements for bundled third-party code (highlight.js BSD-3 notice, gemoji data,
  github-markdown-css MIT notice, Octicons MIT notice for the alert icons from #52)

**Exit criteria:** a v0.1.0 build downloaded from GitHub installs cleanly, passes Gatekeeper, and
updates itself to v0.1.1 via Sparkle.

**Decisions:**

- Acknowledgements (#85): `Acknowledgements/Acknowledgements.json` lists every bundled
  component with its license file (copied verbatim from upstream, source URL recorded; vendored
  sources keep theirs in `Vendor/<name>/LICENSE`). `Acknowledgements/` and `Vendor/` ship in the
  app's resources, and the About panel's credits are built from them in code (`AboutPanel`), not
  a Credits.html (no HTML import, and the text follows dark mode). `AcknowledgementsTests` fails
  when a `Vendor/` folder, a `Package.resolved` pin, or a remote `project.yml` package has no
  entry. Beyond the planned list: LibYAML (inside Yams) and the HTML Standard's entity list
  (`HTMLEntityTable`, BSD-3-Clause in source code). Sparkle's entry is in ahead of #81.
- Updates (#81): Sparkle 2.10.1 (exact pin, app target only). Strictest settings Sparkle has:
  HTTPS feed, `SURequireSignedFeed` (the appcast and release notes are EdDSA-signed by
  `generate_appcast`), and `SUVerifyUpdateBeforeExtraction`; so key rotation needs a Developer ID
  signed DMG, which #82 ships anyway. `SUEnableAutomaticChecks` is unset: Sparkle asks on the
  second launch instead of checking without consent. Settings > General's rows are Sparkle's
  own settings, not keys of ours. Only Release starts the updater; Debug needs
  `-PeepUpdateFeedURL` (the documented manual check against a local appcast is in
  `App/Updates/SoftwareUpdates.swift`), and tests and cold-open measurements never start it.
  The public key is a placeholder (`SPARKLE_PUBLIC_ED_KEY`) until the maintainer runs
  `generate_keys`; Release builds fail until then. One default channel; a beta channel is room
  left in `SparkleUpdater.allowedChannels(for:)` (VISION).
- Homebrew cask (#84): `brew install --cask itspriddle/brews/peep`. The cask's source is
  `Packaging/homebrew/peep.rb` here, not the tap: `scripts/render-cask X.Y.Z SHA256` fills in
  the version and the DMG's sha256, and the release workflow (#83) pushes the result to
  `Casks/peep.rb` in `itspriddle/homebrew-brews` with `HOMEBREW_TAP_TOKEN` (the tap's
  `bump-formula` workflow only handles `Formula/`). `auto_updates true` (Sparkle updates it;
  `brew upgrade` skips it without `--greedy`), `depends_on macos: :sequoia` (`brew style`
  rewrites `">= :sequoia"` to this), and `binary`, `manpage`, and completion stanzas pointing
  into the bundle. `zap` trashes `~/Library/Application Support/Peep` (custom themes included),
  the preferences, saved state, caches (Sparkle's too), HTTPStorages, and WebKit data for
  `now.peep.Peep`; it leaves a link made by Install Command Line Tool… (not Homebrew's to
  remove). The cask's links are Homebrew's: when `<prefix>/Caskroom/peep` exists and
  `<prefix>/bin/peep` is our link, the menu item says Homebrew installed it instead of
  installing a second `peep` (Apple silicon) or offering to uninstall the cask's link from
  `/usr/local/bin` (Intel) (`HomebrewCask`).
- Packaging (#82): `scripts/package-release` (`make release`; `docs/RELEASING.md`) archives
  Release ad hoc and signs every Mach-O itself, inside out (Sparkle's documented order, then the
  helper and the app), with `--options runtime --timestamp`, rather than
  `-exportArchive`: one signing pass the script then checks per Mach-O (team, runtime,
  timestamp, no `get-task-allow` or `application-identifier`), and `codesign --keychain` takes
  CI's throwaway keychain without Xcode needing it. A UDZO DMG (app plus `/Applications` link,
  volume "Peep", no background) is signed, notarized with an App Store Connect API key (or a
  local `notarytool` profile), stapled, mounted, and verified with `codesign` and `spctl`; the
  packaged `peep` is smoke-tested from it. Universal (arm64 and x86_64). The helper needs no
  `com.apple.security.automation.apple-events`: its direct `Peep/odoc` path sends only to its
  own app, which TCC sees as the app sending to itself (tested with a Developer ID, hardened
  runtime build next to a second copy).

## 1.0

A running list of what 1.0 includes, in rough priority order. Each becomes its own milestone
(M7 onward) when it's next; 0.x releases ship along the way.

- **PDF export:** `WKWebView.createPDF`/print pipeline, print-specific CSS per theme, page size,
  margins, headers/footers, `peep --pdf`
- **Math and diagrams:** KaTeX (bundled) for `$…$` / `$$…$$`, optionally Mermaid; requires the
  bundle-only JS policy from M1
- **Outlining and academic styles:** outline mode, APA-style theme (title page, running head,
  references)
- **RTL text:** per-paragraph direction detection (`dir="auto"`), RTL-aware themes
- **Proofreading:** highlight configurable words and phrases to avoid (weasel words, passive
  voice, custom lists) as an overlay toggle
- **Vim plugin:** open/preview the current buffer in Peep with live updates

## Process

1. **Plan a milestone:** in a dedicated session, break the milestone into GitHub issues
   (user-story style, with acceptance criteria) under a matching GitHub milestone in
   `itspriddle/peep` (public).
2. **Work issues:** one branch per issue following
   [Conventional Branch](https://conventional-branch.github.io) (`feature/…`, `bugfix/…`), commits
   following [Conventional Commits](https://www.conventionalcommits.org). Issue branches merge
   into a milestone integration branch; each issue leaves a handoff comment for the next one.
3. **Merge:** one PR per milestone from the integration branch, with tests; CI (`make lint`, core
   tests, app build/tests) must be green.
4. **Close out:** update this roadmap (check off scope, adjust later milestones), then plan the
   next milestone.
