# Vision

## What mdv is

mdv is a fast, native, open-source Markdown **viewer** for macOS. Open a file from Finder, the
terminal, or a pipe and get a well-typeset, faithfully rendered document that updates as the file
changes, styled with plain CSS you can swap or write yourself.

It is for developers reading READMEs and docs, writers previewing drafts from their editor of
choice (Vim, VS Code, anything), and anyone who wants Markdown to look good without opening an
editor or a browser.

## Principles

1. **Native and fast.** Swift and SwiftUI/AppKit. Launches instantly, renders large documents
   without a spinner, feels like a Mac app (documents, tabs, recents, Quick Look-style
   simplicity).
2. **Faithful rendering.** CommonMark and GitHub Flavored Markdown render the way readers expect
   them to on GitHub. Flavors are explicit, not guessed.
3. **Themeable with plain CSS.** Bundled themes (GitHub Primer, a word-processor style, minimal serif) are
   regular stylesheets. Custom themes are a CSS file dropped in a folder. No proprietary theme
   format.
4. **Great from the terminal.** `mdv FILE`, `cmd | mdv`, and headless `mdv --html` are
   first-class, not afterthoughts.
5. **Safe by default.** Markdown files are untrusted input. No remote content, no arbitrary
   JavaScript, no code execution without explicit opt-in.
6. **Extensible where it matters.** Preprocessors (built-in and user scripts) and custom CSS
   cover most customization without a plugin API.
7. **Open and maintainable.** MIT licensed, small dependency footprint, a real test suite, CI on
   every change.

## Non-goals

- **Not an editor.** mdv watches files; your editor edits them.
- **Not on the Mac App Store.** Distributed via GitHub releases and the project site, updated
  with Sparkle. No sandbox constraints.
- **No accounts, sync, or cloud features.**
- **No cross-platform port.** macOS only, using macOS APIs freely.

## Architecture overview

```
 file / stdin ──► custom          ──► MdvCore renderer ──► HTMLDocument ──► WKWebView
                  preprocessor        (frontmatter, flavor, (theme CSS,      (app window,
                  (opt-in user        swift-cmark →         CSP, base URL)   print/PDF)
                   script)            MarkdownNode AST →
                                      transforms → HTML)
                                                └──────► stdout (mdv --html)
```

- **MdvCore** (Swift package): parsing, AST transforms, HTML rendering, frontmatter, themes,
  preprocessors. No UI dependencies; tested with `swift test`.
- **Render pipeline (#51):** every render runs the same stages in this order, enforced in
  `HTMLRenderer.render(_:)` (`HTMLRenderer+Pipeline.swift`):
  1. **Custom preprocessor** (#56/#57, opt-in, off by default): the whole file, frontmatter
     included, through the user's executable (`SourcePreprocessor`;
     `render(_:preprocessor:)` runs it, then the rest). Its output replaces the source for
     every later stage.
  2. **Frontmatter extraction** (`detectsFrontmatter`), in every flavor.
  3. **Flavor resolution:** `RenderOptions.flavor` (the app's default; Settings in #55), or the
     frontmatter's `mdv.flavor` (#54) through `FlavorRegistry`, so frontmatter can change how
     the body parses.
  4. **Parse** the body with the flavor's cmark-gfm extensions.
  5. **AST transforms** (`MarkdownTransform`), the flavor's plus the built-in preprocessors
     turned on in `RenderOptions.builtInPreprocessors`, in one fixed order whatever enabled
     them: alerts (#52), wiki links (#53), emoji shortcodes.
  6. **HTML:** sanitize raw HTML, collect headings and anchors, highlight code, write markup.

  Built-in syntax features ("built-in preprocessors" such as wiki links, and emoji and alerts)
  are AST transforms, not text passes over the source: they rewrite only text nodes the parser
  produced, so code spans, code blocks, raw HTML, and link destinations are never rewritten,
  and Markdown's escaping and code rules aren't re-implemented in a second parser. Nodes they
  add keep the source range of the text they replace, and `HTMLRenderer` writes them, so new
  markup is escaped by construction. Only the custom preprocessor sees raw text.
  **`data-source-line` after a custom preprocessor** refers to lines of the preprocessor's
  output, the text the parser saw, not the file on disk: scroll sync, the outline, and the
  reading position kept across reloads all use those lines consistently. A preprocessor that
  keeps line structure keeps them aligned with the file; one that adds or removes lines shifts
  them (the alternative, a line map from the script, would be a second contract every script
  must honor).
- **Flavors (#51):** a `Flavor` (MdvCore, `Flavors/`) is an id, a display name, the cmark-gfm
  extensions it enables, and the AST transforms it always runs. Bundled: `gfm` (GitHub Flavored
  Markdown, the default: tables, strikethrough, extended autolinks, task lists, footnotes,
  emoji shortcodes, and alerts from #52) and `commonmark` (strict: no extensions, no
  transforms). `FlavorRegistry` resolves ids from settings and frontmatter, like
  `ThemeRegistry`: unknown or missing ids are GFM. **A flavor owns syntax only.** Viewer and
  safety features are independent of it and stay on `RenderOptions`: heading anchors,
  highlighting, source lines, sanitizing, the remote image policy, `linkRoot`, GitHub vs cmark
  markup for GFM nodes, and frontmatter detection and display. Emoji shortcodes are GFM-only:
  they're a GitHub convention, and strict CommonMark means what CommonMark says. CommonMark
  keeps frontmatter detection: frontmatter is metadata, not syntax, and showing a YAML block as
  a paragraph and a `<hr>` would help no one. Opt-in built-in preprocessors (wiki links, #53)
  are toggles independent of the flavor, so they work in CommonMark too. Each bundled flavor has
  its own fixture corpus (`Tests/MdvCoreTests/Fixtures/flavors/<id>/`); GFM is also checked
  against github.com by the README corpus. The spec suite uses `Flavor.spec` (every extension,
  no transforms), which isn't registered.
- **Parsing:** [`swiftlang/swift-cmark`](https://github.com/swiftlang/swift-cmark) (cmark-gfm, the
  engine GitHub uses), called directly through its C API. `MarkdownParser` enables GFM extensions
  and footnotes per the flavor (`RenderOptions.flavor`), never enables smart punctuation, and
  copies cmark's tree into our own `Sendable` `MarkdownNode` AST; no C pointers outlive a parse.
- **Rendering:** `HTMLRenderer` walks the `MarkdownNode` AST and emits HTML (cmark-compatible for
  CommonMark). Owning the AST and the output is what lets us control heading anchors, task lists,
  emoji, raw HTML sanitizing, syntax highlighting, and source-line mapping, and gives the
  pipeline's transforms (above) one tree to operate on.
- **Syntax highlighting:** at render time, in `MdvCore`, so the app and `mdv --html` get the same
  static `<span class="hljs-…">` markup and the viewer needs no JavaScript. A pinned
  [highlight.js](https://highlightjs.org) build (BSD-3, vendored as generated Swift source by
  `make vendor-highlightjs`) runs in an in-process JavaScriptCore context behind the
  `SyntaxHighlighter` protocol. The language comes only from the info string's first word (no
  auto-detection, like GitHub).
- **Display:** `WKWebView`. HTML + CSS is what makes CSS themes, print styles, and PDF export
  possible; SwiftUI-native renderers (e.g. Textual, MarkdownView) can't use stylesheets.
- **App:** AppKit document architecture hosting SwiftUI views. `MarkdownDocument` is an
  `NSDocument` subclass, opened by `NSDocumentController`; each window is a
  `DocumentWindowController` hosting a SwiftUI `DocumentView`, and a per-window
  `WebViewCoordinator` owns the `WKWebView` (loading, in-place content swaps, navigation policy,
  and the scroll/position bridge). The main menu is built in code from per-feature
  contributions. Chosen over SwiftUI `DocumentGroup` (#16) because `NSDocument` gives us, as
  public API, what a viewer needs and `DocumentGroup` hides: a document object that owns
  its file (live reload hangs off it, below), per-window state restoration, tabs, recents, the
  responder chain for menu commands, and a window controller to own the web view. SwiftUI stays
  for window content (find bar, banners, link status); the outline sidebar is AppKit (below).
  The first window's web view is created and starts its web content process first thing at
  launch (`WebViewPrewarmer`, #40), before the document is read, so WebKit's process start
  overlaps the rest of the launch; later windows create their own.
- **Live reload:** each open document watches its file by path with kqueue (`DispatchSource` on
  the file and its folder; `FileWatcher`), debounced 50 ms (capped at 150 ms for a steady
  stream). It handles in-place writes, atomic saves (rename over, swap, Vim's rename-to-backup),
  delete and recreate, and renames (followed, except into the Trash, which counts as a
  deletion). While the document's folder is missing (deleted by `git checkout` or a build
  tool), it watches the nearest existing ancestor and follows the path back down, so the file
  reloads when the folder comes back (#41). Chosen over `NSFilePresenter` (#21), which
  `NSDocument` already is: measured, it
  reported edits from other processes about a second late and went silent for good after a
  delete. Reloads bypass `NSDocument.revert`, which reads on the main thread and reports a bad
  file with an alert: the file is read and rendered off the main actor (a 1 MB document renders in about 0.16 s in a
  Release build, 0.5 s in Debug), stale renders are dropped, and the window swaps the new body
  into the loaded page in place with an app script that keeps the reading position (the top
  source line, or the bottom if the reader was there) in the same script run. Measured on 1 MB:
  the swap takes about 210 ms in WebKit against 230 ms for reloading the page and restoring the
  position, the main thread never stalls more than a few milliseconds either way, and a reload
  can paint the top of the page before the position is restored; so in-place swap, with
  reload-and-restore only when the base URL changes (the file moved). A Vim `:w` of a 20 KB file
  shows in about 100 ms. Unreadable or non-UTF-8 content, and deletion, keep the last render
  under a banner.
- **Opening documents (#22):** AppKit's document paths (Finder, File > Open, Dock drops, Open
  Recent) go through `DocumentController`, which finds an already-open file by file identity
  (symlinks, `/tmp` vs `/private/tmp`) and focuses its window instead of duplicating it. Files
  dropped on a window open as **new tabs** of it; anything else dropped is refused, so WebKit
  never loads a drop. With no windows, launching or clicking the Dock icon shows the Open panel.
  Tabs follow the system "Prefer tabs when opening documents" setting (`tabbingMode`
  `.automatic`, like Preview and TextEdit); Cmd-click on a link always makes a tab. Window
  restoration (documents, frames, tab groups, and each window's reading position as a source
  line) follows the system "Close windows when quitting an application" setting, so
  `mdv FILE` doesn't bring back every old window. Documents whose file is gone or in the Trash
  are skipped quietly. `.md`/`.markdown` are the system's `net.daringfireball.markdown`
  (imported, for a system without it). macOS lists only those two extensions, and an import
  can't add to a system type, so `.mdown`/`.mkd`/`.mkdn` are mdv's own exported
  `<bundle id>.markdown`, conforming to it (on a Mac where another app also declares them,
  Launch Services may pick that app's type, which still conforms to plain text). Plain text
  (`.txt`) opens because it conforms to `public.plain-text`, which mdv reads but never claims
  (`LSHandlerRank None`). Extensionless files (`CHANGELOG`) are `public.data`, which mdv also
  never declares: `DocumentController` types one as plain text (for the Open panel, drops, and
  any other open) only when its first 4 KB is UTF-8 without NUL bytes (`ExtensionlessText`,
  #41). Recent macOS already types a few names (`README`, `INSTALL`) as plain text.
  **The first open renders off the main thread (#32).** `NSDocument` can't be created off main
  (its init is `@MainActor` and traps there under Swift 6, so `canConcurrentlyReadDocuments` is
  out), so `read(from:ofType:)` reads and decodes the file on main, which keeps NSDocument's own
  errors for unreadable and non-UTF-8 files and costs about 1 ms for 5 MB, then renders off the
  main actor. The window appears at once with the theme background (the web view stays hidden
  until its first page loads), titled with the file name until the render names it; while it
  renders, the web view loads an empty page under a `default-src 'none'` CSP, which pays a web
  view's fixed first-load cost (15-30 ms on main, attaching its WebContent process) in parallel
  with the render. A newer read (revert), a live reload, or closing the window drops a render in
  flight. Measured in Debug on a 5 MB document: the render takes about 2.2 s off main and the
  main thread never stalls more than 5 ms (a hang-detector test asserts under one frame); with
  the outline sidebar shown, its first fill adds an AppKit layout of about 15-20 ms when the
  render lands. `Read` and `Render` signposts mark the open path in Instruments' Points of
  Interest.
- **Outline sidebar (#24):** an AppKit sidebar split item (`NSOutlineView`, nested by heading
  level) beside the document, from `RenderedDocument.headings` (raw HTML headings included).
  A click or Return jumps by anchor (`slug`), with the source line as fallback. The current
  section is the last heading at or before the reading position, read a few pixels below the
  top of the view after each `ScrollPosition.js` report (one app-world scroll observer serves
  both restoration and the outline). Over the last viewport height of scrolling that reading
  line moves down to the bottom of the view (#43), so short trailing sections, which can't
  reach the top, each become current in turn. The selection follows scrolling except while
  the reader browses the outline with the keyboard, and a jumped-to heading stays selected
  until the reader scrolls away from where it landed.
  Re-renders keep the sidebar's scroll position, collapsed entries, and selection. Expand All
  and Collapse All (View menu and the sidebar's context menu, #43) act on every entry, nested
  ones included. Visibility and width are per window (restored with the window, #43 for the
  width) and the last toggle is the default for new windows; hidden until first shown. A
  document without headings shows "No Headings".
- **Zoom, print, copy (#26, #47):** zoom is per window. Cmd-+/-/0 set the window's
  `pageZoom` level (Safari's steps), kept by window restoration; a new window starts at
  Settings' default zoom (persisted in `UserDefaults`), so text size is still a reading
  preference rather than a per-file chore. Pinch is the window's `WKWebView` magnification on
  top of it (scales without reflow, as in Safari), also restored; Actual Size resets both, to
  100% rather than Settings' default. Zoom was app-wide in M2 and M3, every window following
  Cmd-+/- live; #47 made it per window because one change re-laid out every open window at
  once, which was jarring. Zoom remembered per file was considered and
  dropped (#43): it would make the same keys mean "this file" or "every file" depending on
  history, and pinch already covers a one-off. Print uses `WKWebView.printOperation` through
  `NSDocument` (Page Setup, Save as PDF from the panel) with `@media print` rules in the theme layers:
  light colors always, full width, wrapped code and tables, no anchor icons, external link
  targets written out. Copy as HTML copies the `mdv --html` body fragment (no
  `data-source-line`, remote images as written) as HTML plus its markup as plain text; Copy
  Markdown Source copies the file as plain text and `net.daringfireball.markdown`. The web
  view's context menu drops browser items the viewer can't perform (Reload, Back/Forward,
  downloads, "Open Image/Media/Frame in New Window"). Copy Link (#42) is taken over from
  WebKit, which copies a relative link's internal `mdv-doc:` URL: it copies the `file:` URL
  the link names, keeping the fragment (`CopyableLink`), and external links as written. The
  `file:` URL, not the link as written, so the copy works outside the document's folder.
- **Find in page (#25):** an app script in the isolated content world (`FindInPage.js`), with
  a SwiftUI find bar above the page and Edit > Find sending the standard
  `performTextFinderAction(_:)` up the responder chain. Chosen over `WKWebView.find`, which
  reports only found / not found (no match count) and marks only the current match, and over
  `NSTextFinder`, whose `WKWebView` integration is not public API (`WKWebView` doesn't
  implement `performTextFinderAction(_:)` or the text finder client protocols). The script
  matches across inline markup but not across blocks, ignores case unless Match Case is on,
  treats the query as literal text with any whitespace matching any whitespace, skips text that
  isn't rendered, and stops counting at 1000. Matches are painted with the CSS Custom Highlight
  API (`::highlight(mdv-find)` rules in the base layer), so the DOM, source-line positions, and
  in-place swaps are untouched and no style is injected. The query and options survive closing
  the bar and every reload: the search runs again after each display (in-place swap or full
  load), keeping the current match number without scrolling. The query follows the system
  find pasteboard (#42): opening the bar or Find Next/Previous takes a search made in another
  app or window since this one last looked, and each new query (typed, or Use Selection for
  Find) is written back. Jump to Selection (Cmd-J, `centerSelectionInVisibleArea(_:)`) scrolls
  the current match while the bar is open, else the page's selection, into view.
- **Default handler:** mdv declares both Markdown types with `LSHandlerRank: Alternate` and
  asks, never grabs (#23); "Make Default" covers both. `Owner` claims a type mdv doesn't define and `Default` lets Launch Services pick
  mdv without asking; both take the choice away from the user. Instead mdv offers once, in a
  non-modal panel, when a document opens while another app is the default ("Not Now" snoozes
  30 days, "Don't Ask Again" is permanent), and Settings > General has "Make mdv the Default
  Markdown Viewer" (#36; it was in the app menu in M2).
- **Themes (#31):** a `Theme` (MdvCore) is plain CSS plus metadata: id, display name, a
  `ThemeBackground` per appearance (the app paints windows and the under-page area with it
  before first paint, and the page's `body` background is generated from it so they can't
  disagree), highlight.js token CSS, and optional print CSS. `ThemeRegistry` is the one place
  the app and `mdv --html` get a theme; a missing, unknown, or deleted id resolves to the
  default (GitHub). Every page is built in three **CSS cascade layers**, declared first with
  `@layer mdv-base, mdv-theme, mdv-user;`, each in its own `<style id="mdv-…">` element so a
  theme switch (#34) or user controls (#37) replace one element's text in place:
  - `mdv-base` (`ThemeBase`): rules viewer features depend on. Its `!important` declarations
    are protected: the cascade reverses layer order for important declarations, so an earlier
    layer's important rule beats any later layer's and any unlayered one. That covers
    `.sr-only`, find highlights (never printed), the remote-image placeholder's visibility,
    `#gh-*-mode-only` hiding, and structural print rules (light color scheme, full width,
    unclipped code and tables, no anchor icons, page breaks). Its other rules (placeholder
    look, link targets written out on paper) are defaults a theme may restyle. Raw HTML
    `style` attributes are stripped, so element-attached styles can't override it either.
  - `mdv-theme`: the theme's CSS. Ordinary declarations beat the base layer whatever their
    specificity, so themes need not know the base selectors.
  - `mdv-user`: user controls (#37), which beat any theme the same way.

  Chosen over concatenation order (base, theme, controls in one sheet), where precedence
  depends on specificity: a theme's `.markdown-body pre { overflow: auto }` would beat the
  base's print `pre { overflow: visible }`, controls would need ever more specific selectors,
  and a custom theme could hide placeholders or find highlights with one `!important`. Theme
  CSS is inlined with every `</` written `<\/` so it can't close its `<style>` element. A theme
  that escapes its layer with a stray `}` becomes unlayered: it then outranks user controls but
  still not the protected base rules; custom themes with unbalanced brackets are rejected (#35).
- **Bundled themes (#33):** GitHub (`github`, the default), Document (`document`, a
  word-processor page; named to avoid Google's trademark), and Serif (`serif`, system serif
  reading column). GitHub vendors `sindresorhus/github-markdown-css` (MIT, pinned in
  `Vendor/github-markdown-css/MANIFEST`, regenerated as Swift by `make
  vendor-github-markdown-css`) rather than hand-writing Primer tokens: it tracks github.com
  closely for free and re-vendoring is one command. The script rewrites its dark block to
  `@media screen and (prefers-color-scheme: dark)` (paper prints light), drops the anchor
  octicon's `data:` `url()` mask, and fails if a release adds anything else to adjust.
  highlight.js tokens map to its Primer syntax variables (`--color-prettylights-syntax-*`),
  so code colors follow github.com in both appearances. All themes use system fonts only and
  leave `.markdown-body` width to the `mdv-user` layer (#37).
- **Reading controls (#37):** content width is a user control; text size is zoom. View >
  Content Width picks one of four presets (Narrow 32em, Theme Default, Wide 72em, Full Width),
  per window like zoom (#47: restored with the window; Settings sets the default for new
  windows), applied live by swapping the `mdv-user` `<style>` text in place (reading position
  kept, no reload). The layer sets
  `--mdv-content-width` and `.markdown-body { max-width: var(--mdv-content-width) }`, screen
  only, so paper is always full width; Theme Default emits nothing. Widths are in `em` of the
  column's font, so the measure holds across themes and zoom levels. There is no separate font
  size control: `pageZoom` (Cmd +/-) already reflows the page at a larger text size, and a CSS
  font size would be a second "bigger text" command that differs only in leaving images,
  padding, and code at their size. #37 made width global because it's a reading preference,
  not a property of the document; #47 reversed that (and zoom with it): changing it re-laid out
  every open window at once. The preference lives on as Settings' default for new windows.
- **Theme picker (#34):** each window has its own theme, picked from View > Theme (bundled themes, then custom ones in their own section), checked in
  the menu, and kept by window restoration (an unknown id shows the default). A pick changes
  that window only; the theme for new windows is Settings' (#36). A switch is an in-place swap, not a reload: an app script replaces the
  `mdv-theme` `<style>` text (`mdv.replaceStyle`, shared with #37) and restores the reading
  position in the same script run, so nothing paints in between; the DOM, find highlights,
  zoom, CSP, and remote-image opt-in are untouched, and the window and under-page background
  change with it. Rejected: reloading the page with the new theme, which loses scroll state
  for a moment, re-runs image loads, and flashes. The rendered content is theme-free
  (`RenderedPage`, shared by a document's windows); each window joins it with its theme
  when it loads a page (off the main actor), and a theme picked mid-load is swapped in when
  the load finishes. Windows resolve their theme id in `ThemeSettings.registry` again
  whenever it changes, so a custom theme edited or deleted on disk (#35) updates or falls
  back live. The fallback for a picked theme that isn't registered (deleted, broken, or not
  loaded yet) is Settings' default theme, and the registry's default (GitHub) only when that
  is missing too (`ThemeSettings.theme(forWindowThemeID:)`, #45); the window keeps its pick and
  shows it again when it returns. Print prints the window's web view, so it uses the window's
  theme; Copy as HTML stays a theme-free fragment.
- **Custom themes (#35):** each `*.css` file in `~/Library/Application Support/mdv/Themes` is a
  theme, id `custom:<file name>` (a namespace no bundled id uses, so it can't shadow one),
  listed in the picker's own section. Metadata is an optional header comment, the first thing
  in the file: `/* mdv-theme` on its first line, then `key: value` lines (`name`, `background`,
  `background-dark` as `#rgb`/`#rrggbb`, `extends`); unknown or repeated keys are errors, so
  typos surface. Name defaults to the file name; `background-dark` defaults to `background`,
  and with neither the extended (else default) theme's backgrounds are used. A comment beat
  `--mdv-background-*` custom properties: it needs no CSS parsing or cascade semantics to read,
  and the window is painted from it before the page exists. Custom themes start from the base
  layer only; `extends: <bundled id>` puts that theme's CSS first in the same layer, so the
  file only overrides (bundled themes only, no chains). Without `extends` there are no
  highlight.js token colors either: a theme written from scratch styles everything it wants,
  code included, rather than inheriting colors chosen for another palette (decided in #45;
  the guide says so). The file is checked by a small CSS
  tokenizer (`CustomThemeCSS`, comments, strings, and escapes aware, so `@\69mport` and
  `u\72l(` are caught) before it is inlined, independent of the CSP: no `@import`, no
  `expression()`, every `url()` (and URL strings in `image-set()`, `image()`, `src()`,
  `cross-fade()`) must be `data:image/…` (images only: the CSP has no `font-src`, and SVG images
  in CSS run no script and load nothing), and `{}`/`()`/`[]` must nest with comments and
  strings closed, so a stray `}` can't leave the theme layer. Rejected rather than stripped,
  so a theme never renders differently than written without saying why. Files must be regular
  files (no symbolic links, opened `O_NOFOLLOW | O_NONBLOCK`), at most 512 KB, UTF-8 without
  NULs; at most 100 themes load. A file that fails is a disabled picker item with the reason
  (and a log line), never an alert. Installed fonts by name are fine. The folder is watched
  with kqueue off the main thread (the folder, each theme file, and while missing its nearest
  existing ancestor), debounced 100 ms (300 ms cap); every burst re-reads the folder and
  replaces `ThemeSettings.registry` only if something changed, so open windows swap an edited
  theme in place (#34) and fall back to Settings' default theme when it is deleted or broken
  (keeping their pick for when it returns). The folder is created on demand (View > Theme > Open
  Themes Folder). The end-user guide is [`docs/THEMES.md`](THEMES.md) (#44); its example theme
  (`docs/example-theme.css`), snippets, and quoted error messages are checked by
  `ThemeGuideTests`.
- **Print themes (#38):** paper is always light and themed. The base layer protects the
  light color scheme and `print-color-adjust: economy` on `:root` and `body`, so no theme
  prints a page background; a theme's dark colors are `@media screen` only. Each bundled
  theme's `printStylesheet` (in `@media print` at the end of its layer) keeps its light fills
  for code, keys, marks, and tables with `print-color-adjust: exact`, so code blocks and diff
  lines stay blocks. Custom themes write their own `@media print` rules and get the same base
  guarantees. WebKit lays a page out at 1.25 CSS px per point of paper width, so 16px prints
  at 12.8pt: GitHub keeps 16px, Document 11pt (about 11.7pt), and Serif drops from 19px to
  15px (12pt) on paper. A `<picture>`'s dark `<source>` never prints: WebKit evaluates
  `prefers-color-scheme` as light while printing and restores the screen's image afterwards
  (checked on PDF output in `AppTests/PrintThemeTests`); rewriting `<source media>` to
  `screen and (...)` was tried and rejected, because WebKit then kept the light image on
  screen after printing.
- **Settings (#36):** App menu > Settings… (Cmd-,) opens one reusable `NSWindowController`
  (`SettingsWindowController`) holding an `NSTabViewController` in toolbar style, one SwiftUI
  `Form` per pane (General today); no SwiftUI `Settings` scene, since the app lifecycle is
  AppKit. It remembers its position and isn't restored at launch. Settings stores nothing of
  its own: `SettingsModel` reads and writes the existing stores (`ThemeSettings`,
  `OutlinePreference`, `ZoomSettings`, `ContentWidthSettings`, `DefaultViewer`), each with an
  injectable `UserDefaults` suite and in memory under UI tests, and follows their change
  notifications, so the View menu and Settings always agree. The default theme, zoom, content
  width (#47), and outline visibility apply to new windows; the View menu changes one window; Settings
  owns the default theme (View > Theme no longer changes it). Settings also lists custom theme
  files that didn't load and has Open Themes Folder (#35). The remote-image opt-in stays per
  window and is not remembered per file: a remembered list of files that may load remote
  content is a privacy record and a standing exception to "no remote content" that the reader
  can forget granting; deferred until there's demand.
- **Visual regression (#39):** `AppTests/ThemeSnapshotTests` opens the showcase fixture
  (`AppUITests/Fixtures/themes/showcase.md`) in each bundled theme in a 900 pt wide window
  (outline hidden, default zoom and width) and captures it light, dark, and printed: screen
  modes with `WKWebView.pdf(configuration:)`, which draws the whole page as the screen shows it
  in the window's appearance, and print through the Save as PDF path. The PDFs are rasterized
  at 1 px per point into sRGB, so the image doesn't depend on the display's scale factor or on
  the window being on screen, and repeated runs are byte-identical. A pixel matches when each
  channel is within 24 of the reference, or (antialiasing, subpixel glyph placement) when it
  and the reference pixel each have a match in the other's 3x3 neighborhood; more than 40
  mismatched pixels, or a different size, fails (a link color or a 1px border width change is
  hundreds). References are per macOS major version (`AppTests/Snapshots/macOS-<major>/`):
  system fonts and text rendering differ between releases, so one tolerance loose enough for
  both would miss real changes, and running only on CI would leave nothing to check locally.
  macOS 26 references are recorded on CI, never on another OS: with
  `MDV_RECORD_MISSING_SNAPSHOTS=1` a missing reference is written to
  `build/theme-snapshots/recorded/` (uploaded as an artifact) and the case passes. Rejected:
  UI test screenshots (window chrome, display scale, and a GUI session that UI tests must
  share) and `takeSnapshot` (visible area only, at the display's scale).
- **CLI:** Swift ArgumentParser tool embedded in the app bundle (`Contents/Helpers/mdv`),
  symlinked onto `PATH` from the app.
- **Tooling:** XcodeGen (`project.yml`), SwiftLint, swift-format, Swift Testing, XCTest UI
  tests, GitHub Actions.
- **Distribution:** Developer ID signing, notarization, Sparkle 2, Homebrew cask.

## Security model

- The rendered page has a strict Content-Security-Policy: no remote loads, inline styles only,
  local/`data:` images only (until a window opts in to `https:` images, below). In the app it is
  `default-src 'none'; style-src 'unsafe-inline'; img-src mdv-doc: data:;`; `mdv --html` output
  keeps `img-src file: data:` so a saved page still shows the images beside it.
- Remote images are blocked by default and are an explicit opt-in **per window** (#20):
  - Blocking happens in `MdvCore` as well as the CSP. `RenderOptions.remoteImages` (`.block`
    in the viewer) replaces every remote Markdown or raw-HTML image with a placeholder that
    shows its alt text and host (sized like the image when raw HTML gives `width`/`height`).
    It drops a `<source srcset>` that names one, and lists them in `blockedRemoteImages`. The
    CSP blocks them on its own as well (tested with raw HTML the sanitizer never sees).
  - When a page has blocked `https:` images, a bar offers "Remote images blocked: Load".
    Loading reloads that window with `RemoteImagePolicy.allowHTTPS` and adds `https:` to
    `img-src`, and nothing else: no `http:` ever, because cleartext images can be read and
    swapped on the wire, so they stay placeholders. Frames, styles, fonts, and media stay blocked.
  - The opt-in lasts for that window until it closes, survives live reloads, and is never
    saved, so reopening a file blocks again. Remembering it per file can come later.
  - `mdv --html` keeps GitHub-compatible output (`.keep`) by default, and its CSP blocks remote
    images when the page is opened. A flag to block them in the HTML itself is M5 work.
  - Tests use servers on 127.0.0.1 and never the network. A document full of remote images
    makes no request, and a page with no CSP does make them (the control).
- The web view never gets `file:` access. The app loads each document at
  `mdv-doc://<window token>/<absolute path>` (a `WKURLSchemeHandler`, chosen over
  `loadFileURL` plus a temp file in #18), so relative URLs resolve against the document, and
  every local read is a decision by `LocalImagePolicy` (MdvCore, unit tested). It serves a file
  only if, after resolving `..`, percent-encoding, and every symlink (`realpath`, then
  `F_GETPATH` on the opened descriptor), it is a regular file inside the allowed root, no larger
  than 32 MB, with a PNG, JPEG, GIF, WebP, or SVG extension whose content sniffs as that same
  format. Anything else gets an empty 404: no listings, paths, or reasons; the page shows a
  broken image. SVG is only ever an `<img>`, where WebKit runs no scripts and loads no
  subresources (tested).
- The allowed root is **the enclosing git work tree's root, else the document's folder**: the
  nearest folder at or above the document containing `.git`, unless that is the home folder or
  `/`. Docs in a repository use `../images/x.png` the way GitHub resolves them, the repository
  is the document's own trust domain, and only images are served from it.
- Root-relative URLs (`/docs/x.png`, `<img src="/...">`, `<source srcset="/...">`,
  `[x](/docs/guide.md)`) resolve against **the same allowed root**, as GitHub resolves them
  against the repository; without a repository that is the document's folder (one rule for
  images and links, and a leading `/` never means the file system root). The renderer rewrites
  them to `<root>/...` (`RenderOptions.linkRoot`, `RootRelativeURL`) with `.`/`..` clamped at
  the root, so `LocalImagePolicy` and `LinkPolicy` see ordinary `mdv-doc` URLs and stay the
  only checks; `//host` stays remote. `mdv --html` and Copy as HTML keep them as written.
- GitHub's `#gh-dark-mode-only` / `#gh-light-mode-only` images (and their remote-image
  placeholders) show only in the matching appearance through the base layer's CSS (`ThemeBase`)
  (`img[src$=...]` under `prefers-color-scheme`), so they follow live appearance changes; print
  shows the light variant. `<picture><source media="(prefers-color-scheme: dark)">` works
  as is (sanitizer and CSP allow it).
- Page JavaScript is disabled (`allowsContentJavaScript = false`): document `<script>`s,
  inline event handlers, and `javascript:` URLs never run, with or without the CSP. The viewer's
  own behavior (scrolling, position tracking, anchor fallback, in-place content swaps) is done by
  app scripts that ship in the bundle (`App/Scripts/`) and run only in an isolated
  `WKContentWorld`, which shares the DOM with the page but not its globals. Swift calls them
  with `callAsyncJavaScript` using fixed function bodies; every value (lines, fragments, HTML)
  is passed as an argument, never spliced into script source. Tests prove page scripts stay
  blocked while app scripts run.
- Raw HTML in Markdown is sanitized per a defined policy rather than passed through blindly.
- Syntax highlighting runs only the vendored highlight.js, in a private JavaScriptCore context
  with no access to the page, files, or network; code and language names are passed as values,
  never spliced into script. Its output is treated as untrusted: it must be nothing but
  `<span class="hljs-…">`, `</span>`, and entity-escaped text whose text equals the original code,
  and is re-serialized before insertion; anything else falls back to plain escaped code.
  JavaScriptCore has no execution time limit, so blocks over 128 KB and code beyond a 256 KB
  per-document budget are left unhighlighted.
- Links go through one tested navigation policy (`LinkPolicy` in `MdvCore`, #19), and nothing
  navigates the viewer away from the document: the only main-frame navigations allowed are the
  page loads the app starts. In-page fragments scroll via the app-script bridge (raw id, then
  percent-decoded, then `user-content-`). `http`, `https`, and `mailto` open in the default app.
  Local Markdown files (`mdv-doc` URLs mapped back to files with the window's token) open in
  mdv; Cmd-click or middle-click opens them in a new tab. Other local files and folders are
  **revealed in Finder, never opened**, so a document can't launch an app or script by link.
  Every other scheme, unmappable `mdv-doc` URL, and blank safe-mode link is blocked silently,
  with the reason shown in the window's link status overlay. Link hover is reported by an app
  script whose message handler exists only in the app's content world; its message is display
  text and never acted on. Find in page passes the query to its app script as a value and
  matches it as literal text; page content never reaches script source.
- Custom preprocessor scripts run only when the user configures them, with a timeout, no shell
  interpolation, and the document passed via stdin. They are the first stage of the render
  pipeline (#51), so their output is still parsed, transformed, and sanitized like any file.
- Hardened runtime, notarized builds, Sparkle updates signed with EdDSA over HTTPS.

## Success looks like

- `mdv README.md` shows a document indistinguishable from GitHub's rendering as fast as a
  `WKWebView` can show it. The original goal, under 200 ms, isn't reachable with `WKWebView`
  (#40): a bare AppKit app that loads the page into one web view first thing at launch paints
  it in about 290-350 ms on a MacBook Air (ROADMAP M3), most of it WebKit starting its web
  content process and drawing the first frames. The agreed target (#40, accepted at the M3
  close-out) is that floor: mdv's cold open stays within about 0-50 ms of the bare app's,
  measured in the same run with `scripts/measure-cold-open -f`.
- Switching themes or editing the file in another app updates the window instantly.
- A new contributor can clone, `make bootstrap && make test`, and be productive in minutes.
