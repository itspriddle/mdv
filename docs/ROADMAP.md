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
| [M4](#m4-flavors-and-preprocessors)     | Flavors and preprocessors      | -         |        |
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
- Performance: the outline's first fill (about 20 ms on main for a 5 MB document with the
  sidebar shown; options: fill after the first load, or lazily while collapsed); no progress
  indicator for long first renders (about 0.4 s of an empty window at 5 MB); no performance
  check in CI (needs a GUI session and Release; CI timing is too noisy); the prewarmed web
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

Control how source becomes Markdown.

- Flavor presets: CommonMark (strict), GFM (default), plus room for others; each a defined set of
  parser options and AST transforms
- Built-in preprocessors (e.g. frontmatter stripping, wiki-links `[[Page]]`, include/transclusion
  TBD)
- Custom preprocessor: user-configured executable, document on stdin, Markdown on stdout,
  timeout and size limits, explicit opt-in with a clear warning
- Per-document overrides via frontmatter (`mdv: { flavor: commonmark, theme: github }`). A
  `theme:` override resolves like a window's pick (M3): bundled or `custom:<file>` ids through
  `ThemeSettings.registry`, falling back to Settings' default; decide whether it beats a theme
  the reader picked for that window, and whether it is remembered by restoration
- Frontmatter display: `RenderOptions` can render frontmatter as a table
  (`FrontmatterDisplay.table`), but nothing in the app exposes it; a Settings option would make
  `table.frontmatter`/`pre.frontmatter` in `docs/THEMES.md` real (update the guide)
- ~~GitHub alerts (`> [!NOTE]`) in the GFM flavor (rendered as plain block quotes in M1)~~ Done (#52)
- Settings UI for flavors and preprocessors
- ~~Carried over from M3: per-window zoom and content width, with Settings setting the default
  for new windows (#47). Restoration keeps each window's values.~~ Done (#47, ahead of M4).

**Exit criteria:** each flavor has its own test corpus; a misbehaving script (hang, crash,
huge output) cannot hang or crash the app.

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
- Per-flavor corpus (#51): `Tests/MdvCoreTests/Fixtures/flavors/<id>/` (`.md` plus recorded
  `.html`, `MDV_RECORD_SNAPSHOTS=1`), one folder per registered flavor; GFM is also checked
  against github.com by the README corpus.
- Custom preprocessor runner (#56): `CustomPreprocessor` in `MdvCore`. The document's path is
  passed in `MDV_DOCUMENT_PATH`, never as an argument. The working directory is the document's
  folder (`/` without a file). The environment is fixed (`PATH` with Homebrew's folders,
  `HOME`, `TMPDIR`, `LANG`). The executable is an absolute path, never looked up on `PATH`,
  and it is validated when configured and again before each run (links followed only for
  the check). Limits: 5 s, 10 MB in, 10 MB out, a 64 KB stderr tail, and `SIGTERM` to the
  process group, then `SIGKILL` 0.5 s later. Its stage 1 adapter is `for(documentURL:)`
  (`SourcePreprocessor`). Fixture scripts cover each misbehavior, and the tests check that no
  process or descriptor leaks. See VISION's security model.

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
- Make `itspriddle/<name>` public; project site / landing page; CONTRIBUTING and issue templates
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
   `itspriddle/mdv` (private until 1.0).
2. **Work issues:** one branch per issue following
   [Conventional Branch](https://conventional-branch.github.io) (`feature/…`, `bugfix/…`), commits
   following [Conventional Commits](https://www.conventionalcommits.org). Issue branches merge
   into a milestone integration branch; each issue leaves a handoff comment for the next one.
3. **Merge:** one PR per milestone from the integration branch, with tests; CI (`make lint`, core
   tests, app build/tests) must be green.
4. **Close out:** update this roadmap (check off scope, adjust later milestones), then plan the
   next milestone.
