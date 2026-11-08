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
| [M5](#m5-cli)                           | CLI                            | -         |        |
| [Gate](#gate-choose-the-name)           | Choose the final name          | -         |        |
| [M6](#m6-distribution-and-10)           | Distribution                   | **1.0**   |        |
| [Post-1.0](#post-10)                    | PDF, math, RTL, proofreading…  | 1.x       |        |

## M0: Foundation

**Status:** Done (2026-11-06).

Get a buildable, tested, linted walking skeleton and a shared plan.

- Swift package `MdvCore` with a minimal renderer (swift-markdown `HTMLFormatter`) and tests
- SwiftUI app that opens `.md` files read-only and renders them in a `WKWebView`
- `mdv` CLI target embedded in the app bundle; `--html` and `--version` work
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
  JavaScriptCore inside `MdvCore`, emitting static class-based spans, so `--html` works and the
  viewer keeps JavaScript off.
- Raw HTML goes through our own allowlist sanitizer modeled on GitHub's (no SwiftSoup); it only
  touches raw-HTML nodes, since renderer output is trusted.
- TOML frontmatter is detected and hidden but not parsed; YAML is parsed with Yams.
- The README corpus is compared with github.com's file view (contents API,
  `application/vnd.github.html`); neither `POST /markdown` mode matches it.
- Generated ids are unique per document: on a collision, footnote ids yield and heading slugs
  keep their GitHub value.

**Exceptions:** [spec](../Tests/MdvCoreTests/Fixtures/spec/exceptions.json) (GFM `tagfilter`
only, permanent: the sanitizer replaces it) and
[README corpus](../Tests/MdvCoreTests/Fixtures/corpus/README.md#exceptions).

**Exit criteria:** GFM spec examples pass (or have documented exceptions); a representative
corpus of READMEs renders to match GitHub; renderer is fuzz/stress tested on large inputs. ✅

## M2: Viewer app

**Status:** Done (2026-11-06).

A pleasant, Mac-native document viewer.

- Open via Finder, Open dialog, drag and drop, recents, Dock; tabs; window restoration
- Offer to become the default `.md` handler
- Live reload on file change, preserving the reading position
- Relative images and links resolve against the file, with scoped file access
- Link handling: local `.md` opens in mdv, anchors scroll, external URLs open in the browser;
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
  launch hooks (`UITestHooks`); the Xcode app target is `MdvApp` so the runner doesn't launch
  the SwiftPM `mdv` CLI.
- **Local resources (#18):** a `WKURLSchemeHandler` (`mdv-doc://<window token>/<absolute
  path>`), not `loadFileURL` plus a temp file; it serves only images that `LocalImagePolicy`
  approves inside the allowed root, the enclosing git work tree or else the document's folder
  (never home or `/`); extension and sniffed format must match. Root-relative `/x` links and
  images resolve against that root, as on GitHub, and `#gh-dark-mode-only` /
  `#gh-light-mode-only` images follow the appearance (CSS).
- **Links (#19):** one tested `LinkPolicy`; the main frame never leaves the document. Local
  Markdown opens in mdv (Cmd-click or middle-click: a new tab); other local files and folders
  are revealed in Finder, never opened; `http`/`https`/`mailto` open in the default app; other
  schemes are blocked silently with the reason in the link status overlay. Fragments try the
  raw id, the decoded id, then `user-content-`. Raw HTML headings get GitHub-style anchors.
- **Remote images (#20):** blocked in `MdvCore` (labeled placeholders) and by the CSP; the
  opt-in is per window, unsaved, and `https:` only; the bar appears only when an `https:` image
  was blocked. `mdv --html` keeps remote images by default (its CSP blocks them when opened).
- **Live reload (#21):** a kqueue watcher by path (measured: `NSFilePresenter` reported other
  apps' edits ~1 s late and went silent after a delete), reading and rendering off the main
  actor, bypassing `NSDocument.revert`; an in-place body swap that keeps the reading position
  (reload-and-restore only when the file moved). Renames are followed; a move to the Trash is
  a deletion; the last render stays under a banner when the file is deleted or unreadable.
- **Opening (#22):** an already-open file is found by identity and focused; drops on a window
  open as tabs; tabs follow the system "Prefer tabs" setting; restoration (including each
  window's reading position) follows the system "Close windows when quitting" setting, so
  `mdv FILE` doesn't bring back old windows (confirmed with the user); with no windows, launch
  and Dock click show the Open panel; plain text opens but is never claimed; `.mdown`/`.mkd`/
  `.mkdn` are mdv's own exported type (the system Markdown type lists only `.md`/`.markdown`).
- **Default handler (#23):** `LSHandlerRank` stays `Alternate`; mdv offers once in a
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
  `mdv --html` body fragment; the web view's context menu drops browser-only items
  (a blocklist, so new system items keep working).
- **Close-out (#27):** AppKit inserts and maintains Open Recent (a code-built one can't be
  marked as the recents menu and showed up twice). The first open of a document still reads
  and renders on the main thread (below); moving it off main needs a background `NSDocument`
  init, which the SDK's `@MainActor` annotation on `NSDocument` traps at runtime under Swift
  6, so it is deferred to M3.

**Crash and hang pass (#27):** `AppTests` (183 tests, including a stress suite: many windows
opened, reloaded, and closed mid-load; files deleted, renamed, and rewritten while open; a
removed folder; malformed and non-UTF-8 files) and `AppUITests` pass under Address Sanitizer
and Thread Sanitizer in Debug with no reports; `MdvCoreTests` under both sanitizers fail only
their wall-clock budgets (sanitizer slowdown). `make test-ui` passed 5 consecutive runs locally
(20 tests, the opt-in restoration test skipped) with no retries; CI (macOS 26, Xcode 26.6)
runs the full UI suite, including restoration, and was green on the merged PR (#28).

**Performance (#27):** cold window open to first paint, measured from process start (the
kernel's start time) to two animation frames after the first page load finished, Release
build, Apple silicon, median of 6 launches with the file as an argument:

| Document | Size | First open read + render (main thread) | Cold open to first paint |
| -------- | ---- | -------------------------------------- | ------------------------ |
| mdv README | 1.7 KB | 3 ms | 372 ms |
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
- Theme model in `MdvCore`: name, stylesheet(s), light/dark variants, optional print CSS
  (print themes; M2 ships basic `@media print` rules); owns the highlight.js token CSS
- Custom themes: CSS files in `~/Library/Application Support/mdv/Themes`, hot-reloaded
- Theme picker per window plus a global default in a Settings window
- Content width controls layered on top of any theme (font size dropped: zoom covers it, #37)
- Theme authoring guide (the only doc written for end users before 1.0)
- Viewer follow-ups from M2:
  - Settings window: theme default, outline default, zoom; move "Make mdv the Default
    Markdown Viewer" there; optionally remember the remote image opt-in per file (deferred, #36)
  - Performance: cold open to first paint under 200 ms for README-sized docs (422 ms in M2;
    replaced by the agreed `WKWebView` floor, #40),
    and the first open's read and render off the main thread (161 ms for 1 MB)
  - Smaller viewer polish, filed as issues: a document folder deleted and recreated isn't
    noticed; extensionless files (`README`) can't be opened from the Open panel; "Copy Link"
    on a relative link copies the internal `mdv-doc:` URL; the find pasteboard

**Decisions:**

- CSS layering (#31): cascade layers, `@layer mdv-base, mdv-theme, mdv-user`, one `<style>` per
  layer. The base layer's `!important` rules (find highlights, placeholders, light/dark-only
  images, structural print rules) can't be undone by any theme; see VISION.
- GitHub theme source (#33): vendor `sindresorhus/github-markdown-css` (MIT, pinned 5.9.0,
  `make vendor-github-markdown-css`), adjusted to screen-only dark and no `url()`; highlight.js
  tokens use its Primer syntax variables. The Docs-style theme is named "Document" (id `document`);
  the serif theme is "Serif" (id `serif`).
- Font size vs zoom (#37): no font size control; zoom (Cmd +/-, reflowing `pageZoom`) is the
  text size control. Content width is four presets (narrow, theme default, wide, full) in
  View > Content Width, global and persisted, applied live via the `mdv-user` layer
  (`--mdv-content-width`); print ignores it. See VISION. **Reversed after M3 (#47):** zoom and
  content width move to per window, like themes, with Settings setting the default for new
  windows. A global change re-laid out every open window at once, which was jarring. Landed;
  VISION's #26 and #37 entries record it.

- Theme switch (#34): in-place swap of the `mdv-theme` `<style>` text by app script (same
  `mdv.replaceStyle` as #37), keeping the reading position, find, zoom, and remote-image
  opt-in; no reload. Theme is per window (restorable); the default for new windows is set in
  Settings (#36). Print uses the window's theme; Copy as HTML stays theme-free.
- Custom theme metadata (#35): an optional leading `/* mdv-theme … */` header comment with
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
  Make mdv the Default Markdown Viewer (moved from the app menu). It surfaces the existing
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
  the floor instead: mdv's cold open stays within about 0-50 ms of the floor's, measured in the
  same run. The floor is a
  bare AppKit app that loads the same page into one `WKWebView` (configured like mdv's) first
  thing at launch, in one plain window (`scripts/cold-open-floor.swift`). mdv is now within
  0-50 ms of it (run to run), and what remains is mostly WebKit's: the web content process takes about 130 ms from the first load to a
  finished page, and the first frames another 40-90 ms, after AppKit is up (about 45 ms) and the
  web view exists (about 50 ms). mdv starts its first window's web view first thing at launch
  (`WebViewPrewarmer`), so that bring-up overlaps the rest of the launch, the document read, and
  the window build. A regression is anything clearly slower than the floor, measured in the same
  sitting (`scripts/measure-cold-open -f`). See VISION.
- Opening and live reload edge cases (#41): while the document's folder is missing, the
  watcher sits on the nearest existing ancestor and follows the path back down; extensionless
  files that sniff as UTF-8 text open as plain text (`DocumentController.canOpen(_:)`, the one
  rule for the Open panel and drops). mdv still declares only Markdown (`Alternate`) and plain
  text (`None`), never `public.data`.
- Copy Link and find (#42): Copy Link never copies an `mdv-doc:` URL (`CopyableLink`); the find
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
- Dragging a link out of the page, Share on a link, and Copy Image no longer expose `mdv-doc:`
  URLs (`PasteboardLinkRewriter` in MdvCore). Copy Image of a local image copies the file's
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
| mdv README | 1.7 KB | 398 ms | 341 ms | 348 ms |
| `bat` README (corpus) | 34 KB | 415 ms | 363 ms | 376 ms |
| Synthetic | 1 MB | 645 ms | 646 ms | |
| Synthetic | 5 MB | 1945 ms | 1921 ms | |

The gain varies with how long WebKit takes to start its content process: 13-78 ms for the
README across runs. The bare app's numbers include no menus, toolbar, sidebar, or SwiftUI;
mdv's come within 0-50 ms of it (another sitting: 338 ms vs 287 ms), because WebKit, not mdv,
is most of the critical path.

**Crash and hang pass (#45):** `AppTests` (289 tests, including the stress suite, extended with
theme switches racing rapid live reloads and a custom themes folder edited, broken, deleted, and
refilled while windows open and close) and `AppUITests` (33 tests, restoration included) pass
under Address Sanitizer and Thread Sanitizer in Debug, with no sanitizer reports. The Thread
Performance Checker flagged one priority inversion in mdv's code: the YAML frontmatter parser's
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
| mdv README | 1.9 KB | 333 ms | 336 ms (344) | 305 ms (300) | +31 ms (+44) |
| `bat` README (corpus) | 34 KB | 360 ms | 360 ms (389) | 328 ms (324) | +32 ms (+65) |
| Synthetic | 1 MB | 674 ms | 658 ms (682) | | |
| Synthetic | 5 MB | 2092 ms | 2069 ms (2146) | | |

mdv stays within the agreed 0-50 ms of the floor in the interleaved run (the separate run's
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
- Theme guide: screenshots; its paths say `mdv` (rename with the app before M6); `@font-face
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
  activation while the bar is open; dropping an extensionless file from Finder and `mdv
  CHANGELOG` are manual checks only; the Open panel sniffs every extensionless file it lists
  (fine locally, maybe slow on a large network folder); while a document's folder is missing,
  the watcher may sit on a busy ancestor such as `~`.
- Outline: the sidebar width is per window; new windows don't inherit the last width.

**Exit criteria:** switching themes is instant; a custom CSS file appears and updates without
restart; bundled themes pass a visual regression check. ✅ (automated checks; the manual
checklist is in the milestone PR)

## M4: Flavors and preprocessors

**Status:** Done (2026-11-08; the milestone PR, #60, merges after review).

Control how source becomes Markdown.

- Flavor presets: CommonMark (strict), GFM (default), plus room for others; each a defined set of
  parser options and AST transforms (#51)
- Built-in preprocessors: wiki links `[[Page]]` (#53); frontmatter is extracted in every flavor
  and shown hidden or as a table. Include/transclusion: not done (deferred, below)
- Custom preprocessor: user-configured executable, document on stdin, Markdown on stdout,
  timeout and size limits, explicit opt-in with a clear warning (#56, #57)
- Per-document overrides via frontmatter (`mdv: { flavor: commonmark, theme: github }`, #54).
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
  flavor resolution (frontmatter `mdv.flavor`, #54) → parse → AST transforms → HTML, in
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
  separate HTML blocks) is top level in mdv's tree, so it becomes an alert; github.com keeps it
  a block quote.
- Settings > Markdown (#55): default flavor, frontmatter display (hidden or a table), and
  opt-in built-in preprocessors in one `MarkdownSettings` store; changes re-render open
  documents in place (the live reload swap, reading position kept), and frontmatter
  `mdv.flavor` (#54) still wins. No per-window flavor menu: flavor belongs to the file
  (frontmatter) or the reader's one default, and is per document, not per window. The bundled
  themes already style `table.frontmatter` and `pre.frontmatter` (light, dark, print); no theme
  CSS or snapshot change. See VISION.
- Wiki links (#53): an opt-in built-in preprocessor (Settings > Markdown, or `mdv.wikilinks`,
  which beats Settings both ways), independent of the flavor. `[[Page]]`, `[[Page|label]]`
  (label second, unlike Gollum), `[[Page#Heading]]`, `[[#Heading]]`; plain text only, brackets
  written as is (`\[[` stays literal, checked against the source line). GitHub wiki naming
  (`Page Name` → `Page-Name.md`, case-insensitive, space = hyphen, Markdown extensions only).
  Searched in the document's folder, then the allowed root breadth first, never outside it,
  skipping hidden entries and symbolic links, capped at 10,000 entries. MdvCore takes an
  injected `WikiLinkResolver` (`FolderWikiLinkResolver` over an injected folder reader; the app
  reads the disk). Found: a relative, percent-encoded `a.wikilink` through `LinkPolicy`;
  missing: `a.wikilink.wikilink-missing` with no `href` (dashed underline from the base
  layer, no theme CSS or snapshot change). Resolved at render time only; `mdv --html` has no
  resolver yet (M5). Fixtures `Fixtures/flavors/*/wiki-links*.md`. See VISION.
- Per-flavor corpus (#51): `Tests/MdvCoreTests/Fixtures/flavors/<id>/` (`.md` plus recorded
  `.html`, `MDV_RECORD_SNAPSHOTS=1`), one folder per registered flavor; GFM is also checked
  against github.com by the README corpus.
- Per-document overrides (#54): `DocumentOverrides` (MdvCore) reads `flavor`, `theme`, and
  `wikilinks` from the YAML frontmatter's `mdv:` mapping; other keys and wrong types are
  ignored and reported in `RenderedDocument.overrides`. Presentation only: frontmatter can't
  enable the custom preprocessor, turn off sanitizing, allow remote images, or change any other
  setting (`RenderOptions.applying(_:)` touches only the flavor; tests prove each). The flavor
  beats `RenderOptions.flavor` before parsing (`mdv --html` too); an unknown one keeps the
  reader's default. Theme precedence: the window's View > Theme pick, then the document's
  theme, then Settings' default; same fallback as a pick. Restoration saves only the pick. A
  live reload that changes `mdv.theme` swaps the theme in place. View > Theme checks the shown
  theme and has "Document's Theme" to drop the pick. TOML `[mdv]` is unsupported (documented,
  reported as ignored); no TOML parser. `mdv --html` uses a bundled frontmatter theme. See
  VISION.
- Custom preprocessor runner (#56): `CustomPreprocessor` in `MdvCore`. The document's path is
  passed in `MDV_DOCUMENT_PATH`, never as an argument. The working directory is the document's
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
| mdv README | 4.4 KB | 336 ms | 335 ms | 298 ms | +37 ms |
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

- UI tests hold up renders with a Debug-only launch hook, `-MdvUITestRenderDelay <seconds>`
  (`UITestHooks.renderDelay`, compiled out of Release, at most 30 s, cancelled with the
  render), instead of a 4 s preprocessor script, which a slow CI launch could outlast.
- When `posix_spawn` refuses a preprocessor that passed the executable check (`EPERM` or
  `EACCES`), the bar's reason adds a likely cause without claiming it: the file may be
  quarantined (downloaded, or saved by a sandboxed app), with `xattr -d com.apple.quarantine`
  and System Settings > Privacy & Security to try. Seen with scripts the sandboxed UI test
  runner writes; a quarantined script launched from a terminal ran, so the cause isn't
  confirmed for downloads.
- The GitHub repository became public (it was to stay private until 1.0); M6 renames it rather
  than publishing it.

**Crash and hang pass (#59):** `AppTests` (365 tests, including the stress suite) and
`AppUITests` (46 tests, restoration included, run separately with
`TEST_RUNNER_MDV_UI_TEST_RESTORATION=1`) pass under Address Sanitizer and Thread Sanitizer in
Debug, with no sanitizer reports and no runtime issues from mdv's code. The stress suite gained
`StressTests+Markdown`:

- Settings > Markdown (flavor, frontmatter table, wiki links) changing during first renders
  (a 1 MB document among them) and rapid live reloads;
- frontmatter `mdv.theme` and `mdv.flavor` changing under rapid live reloads, with the reader
  picking and dropping a theme and changing both defaults meanwhile;
- one preprocessor script that hangs, crashes, floods stdout, or fails depending on the file,
  switched by live reload, with its arguments changing mid-run.

Each ends on the newest content and settings, with no process left. No app bug turned up.

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
  to CommonMark"; no UI for `RenderedDocument.overrides.ignored` (frontmatter keys mdv ignored
  and why).
- Alerts: a quote between raw HTML blocks (`<details>` … `</details>`) becomes an alert where
  github.com keeps a block quote (known divergence, #52); titles are always English, as on
  GitHub.
- Wiki links: `mdv --html` has no resolver, so page links render as missing there (M5); a link
  to a heading goes to the first heading with that text (slugs aren't de-duplicated against the
  target); no tooltip on missing links; a `.markdown` and `.md` tie in one folder goes to name
  order; targets appearing or disappearing don't re-render (the next render picks them up).
- Custom preprocessor: non-UTF-8 sources can't be converted (the file must decode as UTF-8
  first); the runner is not a sandbox (`setsid` escapes the group); the quarantine hint is
  unconfirmed for downloaded scripts (no reproduction outside the UI test runner).
- Slow renders: the corner indicator hides when the render lands, not when the in-place swap
  finishes (a few hundred ms more at 5 MB); no indicator while a reload only reads the file.
- Settings > Markdown: the flavor picker's note doesn't mention that frontmatter `mdv.flavor`
  wins.

## M5: CLI

Make the terminal workflow excellent.

- `mdv FILE...` opens files in the running app (or launches it)
- `cmd | mdv` streams stdin into a new window without leaving files behind in temp
  directories longer than needed
- `--theme NAME`, `--flavor NAME`, `--html` / `--output FILE`, `--standalone` (inline CSS).
  M3 settled the pieces: `ThemeRegistry` is the one place the CLI gets a theme (unknown ids fall
  back to GitHub), pages are three cascade layers (`ThemeLayer`), and custom themes load with
  `CustomThemeFolder` (MdvCore). Decide whether `--theme` accepts custom themes (`custom:<file>`
  from the Themes folder) and whether `mdv FILE --theme X` sets that window's theme in the app
- What M4 settled for the CLI:
  - **`--flavor NAME`:** ids come from `FlavorRegistry.bundled` (`gfm`, `commonmark`) and set
    `RenderOptions.flavor`. Today frontmatter `mdv.flavor` beats `RenderOptions.flavor` inside
    MdvCore (`RenderOptions.applying(_:)`), as it beats Settings' default in the app. Decide
    whether an explicit `--flavor` beats the document (as a window's theme pick does, and as
    VISION says `--theme` will); if so MdvCore needs a way to apply every override but the
    flavor. An unknown `--flavor` should be a usage error, not a silent fallback (frontmatter
    falls back because documents are untrusted; flags are the reader's).
  - **Frontmatter overrides in headless output:** `mdv --html` already applies `mdv.flavor`
    and `mdv.wikilinks` (in MdvCore) and uses a bundled `mdv.theme` for its page (custom or
    unknown ids are GitHub). `--theme` should beat `mdv.theme`; `custom:` ids need
    `CustomThemeFolder`.
  - **Custom preprocessor:** `mdv --html` doesn't run it. Recommendation: keep it off unless a
    flag asks for it (headless output of an untrusted file shouldn't run a program implicitly,
    and the app's setting is an app preference). The runner is in MdvCore (`CustomPreprocessor`;
    `documentURL: nil` for stdin gives cwd `/`), so a flag is a few lines; decide whether it
    reads the app's configured program or takes a path.
  - **Settings > Markdown:** `mdv --html` uses `RenderOptions` defaults (GFM, frontmatter
    hidden, no wiki links), not the app's Settings. Decide whether the CLI reads them; flags are
    the reproducible default.
  - **Wiki links:** `mdv --html` has no `WikiLinkResolver`, so page links render as missing
    (`[[#Heading]]` works). Pass a `FolderWikiLinkResolver` with a file system reader (move the
    app's `FileSystemFolderReader` into MdvCore or the CLI) and the document's allowed root
    (`LocalResourceRoot.forDocument(at:)`); none for stdin.
- Flags for M1's render options: frontmatter table, sanitize, source lines, highlighting, and
  remote images (`--html` keeps them, as GitHub does, unless asked to block them; #20)
- `--wait` blocks until the window closes (for `$EDITOR`-style and git workflows)
- "Install command line tool" menu item (symlink to `/usr/local/bin` or `~/.local/bin`), plus
  uninstall
- Shell completions (ArgumentParser-generated) and a man page
- CLI integration tests

**Exit criteria:** every example in the README works; CLI tests run in CI.

## Gate: choose the name

Before distribution work starts, pick the final name. Bundle identifier, repository name, Sparkle
feed URL, Homebrew cask, and website all depend on it, and changing them after release breaks
updates. Rename `PRODUCT_BUNDLE_IDENTIFIER_BASE`, targets, and docs in one pass.

## M6: Distribution and 1.0

Ship it.

- Developer ID signing and notarization in CI (secrets in GitHub Actions; signing identity never
  committed)
- DMG (or zip) packaging with app and CLI
- [Sparkle 2](https://sparkle-project.org): EdDSA signing keys, appcast hosted on GitHub Pages or
  the project site, update channel settings
- Tag-driven release workflow: build → sign → notarize → staple → publish GitHub Release → update
  appcast
- Version bumping keeps `MARKETING_VERSION` and `MdvInfo.version` in sync
- Homebrew cask
- Rename `itspriddle/mdv` to the final name (public since M4's close-out); project site /
  landing page; CONTRIBUTING and issue templates
- Acknowledgements for bundled third-party code (highlight.js BSD-3 notice, gemoji data,
  github-markdown-css MIT notice, Octicons MIT notice for the alert icons from #52)

**Exit criteria:** a 1.0 build downloaded from GitHub installs cleanly, passes Gatekeeper, and
updates itself to 1.0.1 via Sparkle.

## Post-1.0

Rough priority order; each becomes its own milestone when it's next.

- **M7 PDF export:** `WKWebView.createPDF`/print pipeline, print-specific CSS per theme, page size,
  margins, headers/footers, `mdv --pdf`
- **M8 Math and diagrams:** KaTeX (bundled) for `$…$` / `$$…$$`, optionally Mermaid; requires the
  bundle-only JS policy from M1
- **M9 Outlining and academic styles:** outline mode, APA-style theme (title page, running head,
  references)
- **M10 RTL text:** per-paragraph direction detection (`dir="auto"`), RTL-aware themes
- **M11 Proofreading:** highlight configurable words and phrases to avoid (weasel words, passive
  voice, custom lists) as an overlay toggle
- **M12 Vim plugin:** open/preview the current buffer in mdv with live updates

## Process

1. **Plan a milestone:** in a dedicated session, break the milestone into GitHub issues
   (user-story style, with acceptance criteria) under a matching GitHub milestone in
   `itspriddle/mdv` (public).
2. **Work issues:** one branch per issue following
   [Conventional Branch](https://conventional-branch.github.io) (`feature/…`, `bugfix/…`), commits
   following [Conventional Commits](https://www.conventionalcommits.org). Issue branches merge
   into a milestone integration branch; each issue leaves a handoff comment for the next one.
3. **Merge:** one PR per milestone from the integration branch, with tests; CI (`make lint`, core
   tests, app build/tests) must be green.
4. **Close out:** update this roadmap (check off scope, adjust later milestones), then plan the
   next milestone.
