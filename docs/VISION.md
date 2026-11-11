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
  3. **Document overrides and flavor resolution (#54):** the frontmatter's `mdv:` mapping
     (`DocumentOverrides`) is applied with `RenderOptions.applying(_:)`: a registered
     `mdv.flavor` beats `RenderOptions.flavor` (the app's default, Settings > Markdown, #55), so
     frontmatter can change how the body parses; an unknown one leaves `RenderOptions.flavor`.
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
  **GitHub alerts (#52)** follow github.com's rules, verified against its renderer (see
  `GitHubAlerts`): a top-level block quote whose first line is `[!NOTE]`, `[!TIP]`,
  `[!IMPORTANT]`, `[!WARNING]`, or `[!CAUTION]` alone (any case), with a body after it,
  becomes GitHub's `div.markdown-alert` markup. The title and Octicon SVG are renderer
  constants, so they are trusted output and need no CSP change.
  **`data-source-line` after a custom preprocessor** refers to lines of the preprocessor's
  output, the text the parser saw, not the file on disk: scroll sync, the outline, and the
  reading position kept across reloads all use those lines consistently. A preprocessor that
  keeps line structure keeps them aligned with the file; one that adds or removes lines shifts
  them (the alternative, a line map from the script, would be a second contract every script
  must honor).
- **Flavors (#51):** a `Flavor` (MdvCore, `Flavors/`) is an id, a display name, the cmark-gfm
  extensions it enables, and the AST transforms it always runs. Bundled: `gfm` (GitHub Flavored
  Markdown, the default: tables, strikethrough, extended autolinks, task lists, footnotes,
  emoji shortcodes, and GitHub alerts) and `commonmark` (strict: no extensions, no
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
- **Per-document overrides (#54):** a document can set `flavor`, `theme`, and `wikilinks`
  (#53) in an `mdv:` mapping in its YAML frontmatter (`DocumentOverrides`, MdvCore,
  `Overrides/`). Presentation only; see the security model. Each key is read into a typed
  field (ids trimmed; flavor and bundled theme ids lowercased, `custom:` ids kept as written;
  `wikilinks` takes YAML 1.2 `true`/`false`), and `RenderOptions.applying(_:)` is the one place
  a field changes a render. Unknown keys and wrong types are ignored, never an error page, and
  reported in `RenderedDocument.overrides.ignored` with a reason. The flavor is applied in
  MdvCore before parsing, so `mdv --html` gets it too; the theme is reported for the caller to
  resolve (the app below; `mdv --html` through `ThemeResolver`, #64, where `--theme` beats
  it). **TOML `[mdv]` is unsupported** (documented): TOML frontmatter isn't
  parsed (no TOML parser, and none added for this); a TOML block that mentions `mdv` is reported
  as ignored. `RenderOptions.appliesDocumentOverrides` turns overrides off (spec mode does).
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
  main thread never stalls more than 5 ms (a hang-detector test asserts under one frame), with
  the outline sidebar shown or hidden. `Read` and `Render` signposts mark the open path in
  Instruments' Points of Interest.
  **Feedback for slow renders (#58).** A wait that outlasts 300 ms shows an indeterminate
  progress indicator (`RenderProgress`, a SwiftUI overlay on the web view); shorter waits never
  flash it. Before a window's first page loads, it sits in the middle of the blank page on the
  theme's background, drawn in the appearance that contrasts with that background
  (`ThemeColor.isDark`), and goes the moment the page loads. A re-render over a shown page (a
  live reload, a Settings change, a slow custom preprocessor) never blanks the window: the old
  page stays, readable and scrollable, with a small indicator on a material circle in its top
  corner until the new page lands. That one is subtle on purpose: a reader editing a large file
  or using a slow script should see that the window is behind, without anything covering the
  text or taking clicks. The outline sidebar's first fill (an AppKit layout of about 15-20 ms on
  main for a 5 MB document with the sidebar shown) runs after the first page has painted (two
  animation frames, or 100 ms for a window WebKit isn't drawing), not when the render lands, so
  it is off the first paint's critical path; the sidebar is blank, not "No Headings", until
  then. Later renders fill it as they are shown.
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
- **Frontmatter theme (#54):** a document's `mdv.theme` resolves like a window's pick (bundled
  or `custom:<file>` ids through `ThemeSettings.registry`, same fallback). Precedence: the
  reader's View > Theme pick for that window, then the document's theme, then Settings' default
  as it was when the window opened (`DocumentWindowController.themeID`). The reader chose
  explicitly for that window, so the pick wins; a document's theme is the author's suggestion
  and beats only the general default. **Restoration remembers only the explicit pick**, so a
  frontmatter theme edited while the app was closed applies on relaunch, and a window that
  followed the document keeps following it. **Live reload:** the theme id travels with the
  rendered page (`RenderedPage.documentThemeID`, shared by the document's windows), and a
  reload that changes it swaps the stylesheet in place (#34's path), unless the window has a
  pick; a changed `mdv.flavor` re-renders like any edit. **View > Theme** checks the theme the
  window shows, whatever chose it, and starts with "Document's Theme (<name>)", enabled while a
  pick hides the document's theme, which drops the pick. Rejected: a frontmatter theme beating
  the reader's pick (the reader couldn't override a document they dislike), and restoring the
  shown theme (a stale frontmatter theme would stick after the file changed). The first paint
  of a window uses Settings' default background until the first render lands with the
  document's theme (a frame or two, while the web view is still hidden).
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
  `Form` per pane (General, and Markdown since #55); no SwiftUI `Settings` scene, since the app lifecycle is
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
- **Wiki links (#53):** an opt-in built-in preprocessor (`WikiLinks`, an AST transform), off
  by default and turned on by Settings > Markdown or a document's `mdv.wikilinks`, which beats
  Settings both ways. Independent of the flavor. Settled rules:
  - **Syntax:** `[[Page]]`, `[[Page|label]]`, `[[Page#Heading]]`, `[[Page#Heading|label]]`,
    and `[[#Heading]]` (same document). Label after the first `|` (the Obsidian and MediaWiki
    order; GitHub's Gollum puts the label first, which mdv doesn't follow), heading after the
    first `#`; `\|` in table cells. Only in plain text, all within one run: never in code, raw
    HTML, link text, autolinks, or alt text, and not across emphasis. The brackets must be
    written as is: `\[[`, `[\[`, `\]]`, and `&#91;[` stay literal. cmark merges escaped and
    plain text into one node, so the transform lines each candidate node up with its source
    line (`SourceLines`); a node it can't line up keeps its brackets literal (a missed link,
    never an escape ignored). Targets over 1,024 bytes stay literal.
  - **Naming (GitHub wiki rules):** `Page Name` is `Page-Name.md`; case-insensitive, and a space
    matches a hyphen, so `Page Name.md` (note apps) works too. Only Markdown extensions
    (`LinkPolicy.markdownExtensions`). `[[Page.md]]` names that file. Folders in the name
    (`[[guides/Setup]]`) must match the file's folders; empty parts, `.`, `..`, a leading `/`,
    and control characters name nothing.
  - **Search scope:** the document's folder first, then every folder under the allowed root
    (`LocalResourceRoot`: the git work tree, else the document's folder) breadth first, so the
    match nearest the root wins; never outside the root. Hidden entries and symbolic links are
    skipped, entries are taken in name order, and the root search stops after 10,000 entries
    (`FolderWikiLinkResolver.defaultEntryLimit`), so a huge repository can't stall a render.
    MdvCore stays filesystem-free: the renderer takes an injected `WikiLinkResolver`, the search
    rules are `FolderWikiLinkResolver` over an injected `WikiLinkFolderReader`, and the app
    supplies the file system reader (`DocumentWikiLinks`). `FileSystemFolderReader` (regular
    files and folders only) lives in MdvCore so `mdv --html` uses the same one (#65,
    `FolderWikiLinkResolver.fileSystem(forDocumentAt:root:)`); standard input has no resolver,
    so its page links are missing.
  - **Output:** a found page is `<a class="wikilink" href="Page-Name.md#slug">`, its path
    relative to the document with every part percent-encoded (nothing in a name can add a
    scheme, query, or attribute), so it goes through `LinkPolicy` like any relative link (opens
    in mdv, Cmd-click in a new tab) and Copy as HTML stays portable. The heading maps to
    `HeadingSlug` of its text (the target's first heading with that text). A missing page is
    `<a class="wikilink wikilink-missing">` with no `href`, so it can't navigate; the base layer
    gives it a dashed underline. The label is text, escaped by `HTMLRenderer`.
  - **Resolved at render time only:** a target appearing or disappearing doesn't re-render the
    linking document; the next render (an edit, a Settings change, a reopen) picks it up. A
    resolver is made per render and caches only within it.
- **Settings > Markdown (#55):** a second Settings pane (`MarkdownSettingsView`) for how
  documents are read: the default flavor (from `FlavorRegistry`), frontmatter hidden or shown
  as a table (`FrontmatterDisplay`), and opt-in built-in preprocessors (the Wiki links toggle,
  #53; the section is hidden if none is offered), with room below for the custom preprocessor (#57).
  One store, `MarkdownSettings`, holds all three and posts one change notification; a render
  gets them as a `MarkdownPreferences` value read on the main actor, never by reading the store
  off it. Unlike the window defaults above, these apply to **open documents at once**: each
  `MarkdownDocument` renders its source again off the main actor and its windows swap the
  result in place like a live reload (no page load, reading position kept). `DocumentContent`
  records the preferences it was rendered with, so a first render or live reload that started
  before a change is rendered again when it lands. The default flavor is only
  `RenderOptions.flavor`; a document's frontmatter `mdv.flavor` (#54) overrides it in MdvCore.
  Copy as HTML uses the preferences the window's page was rendered with.
  **No per-window flavor menu** (no View > Flavor): the flavor describes how a file was written,
  not how the reader likes to read it, so it belongs to the file (frontmatter, #54) or to the
  reader's one default; a third, per-window level would need restoration, another precedence
  rule against frontmatter, and would make two windows on one document disagree about its
  syntax (flavor is per document, themes are per window).
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
  - Structure (#63): the command is the `MdvCLIKit` library (`CLI/MdvCLIKit`); the executable
    (`CLI/Main`, SwiftPM's `MdvCLI` and Xcode's `mdv-cli`) only calls `MdvCommand.main()`.
    Each concern is an `@OptionGroup` in its own file: `InputOptions` (FILE, `-`, stdin),
    `OutputOptions`, `ThemeFlavorOptions`, `RenderFlagOptions`, `PreprocessorOptions`,
    `AppOpenOptions`. `MdvCommand.validate()` holds rules that span groups.
    `execute(in: CLIEnvironment)` runs against injected standard streams and an `AppOpening`
    opener; `MdvCLITests` (under `swift test`) calls it in-process and runs the built binary
    end to end.
  - Output (#63): `--html` prints a complete page, which is already standalone (inline CSS,
    strict CSP, no external resources), so the roadmap's `--standalone` was dropped.
    `--fragment` prints the body HTML only (no `<html>`, `<head>`, or CSS) and implies `--html`.
    `-o`/`--output FILE` implies `--html`, writes atomically (temp file renamed over FILE), and
    refuses an output that is one of the inputs (same device and inode, so symbolic and hard
    links count). `-o -` is standard output.
  - Several inputs (#63): only `--fragment` prints several to one output (in argument order);
    several full pages, or `--output` with several inputs, is a usage error, because
    concatenated pages aren't one HTML document. An `--output-dir` was left out until someone
    needs it. Every input is read and rendered before anything is written, so a bad input
    leaves no partial output.
  - Errors and exit codes (#63, `sysexits(3)`): 64 usage (ArgumentParser's errors, several
    pages to one output, `--output` naming an input, no FILE while standard input is a
    terminal), 65 input not UTF-8 (or standard input over 10 MB for a window, #68), 66 input
    missing or unreadable (POSIX message: `No such file or directory`, `Is a directory`,
    `Permission denied`; or empty standard input for a window, #68), 69 the app couldn't be opened, 70 the
    `--preprocessor` program couldn't run or failed (#66), 73
    `--output` not writable, 74 writing standard output failed. Errors are one `mdv: <file>:
    <reason>` line on standard error. `ExitStatus` is the list; `--help` and the README repeat it.
  - Standard input (#63): with no FILE, mdv reads standard input, unless it is a terminal; then
    it prints usage and exits 64 rather than waiting silently. `-` reads standard input
    explicitly (once), even from a terminal.
  - Theme and flavor (#64): **precedence is flag > frontmatter > default**, as a window's
    View > Theme pick beats `mdv.theme`: a flag is the reader's explicit choice for this run.
    `--flavor` sets `RenderOptions.flavor` and pins it (`RenderOptions.pinnedOverrides`, checked
    in `RenderOptions.applying(_:)`), so `mdv.flavor` doesn't replace it while the document's
    other overrides (`wikilinks`) still apply; `RenderedDocument.flavor` reports the flavor used.
    Pinning only keeps the caller's own presentation setting; no safety setting goes through it.
    `--theme` takes a bundled id (lowercased) or `custom:<file name>`, resolved by
    `ThemeResolver` (MdvCLIKit, reused by `mdv FILE --theme`): custom themes load through
    `CustomThemeFolder` with the app's checks, and an id is only matched against the folder's
    files, never used as a path. Flags are the reader's, so an unknown `--flavor`/`--theme` is a
    usage error (64), a missing custom theme 66, and one failing its checks 65, each with the
    reason; frontmatter is untrusted, so its theme falls back to GitHub silently. Without
    `--theme`, a `custom:` `mdv.theme` now loads too (same folder, same checks as the app). The
    folder is `~/Library/Application Support/mdv/Themes` (the app's), overridable with
    `MDV_THEMES_FOLDER` (tests always set it or inject `CLIEnvironment.themesFolder`). The CLI
    doesn't read the app's default-theme setting; its default is GitHub. `--list-themes` and
    `--list-flavors` print `id<TAB>name` lines (for completions, #71); theme files that don't
    load are reported on standard error.
  - Render flags (#65, `RenderFlagOptions`, help section "Rendering"): `--frontmatter
    hidden|table`, `--wiki-links`/`--no-wiki-links` (pins `.wikiLinks`, so it beats
    `mdv.wikilinks`; off by default), `--source-lines`, `--no-highlight`,
    `--no-heading-anchors`, `--block-remote-images` (#20's placeholder; kept by default, as
    GitHub does). They change HTML output only, so without `--html`, `--fragment`, or `--output`
    they are a usage error (64). **The CLI never reads the app's Settings > Markdown**: flags
    only, so the same command gives the same output whatever the app is set to.
  - File inputs resolve root-relative URLs and wiki links as the app does: `linkRoot` is the
    allowed root (`LocalResourceRoot`), so `/docs/x.png` becomes `<root>/docs/x.png`, an
    absolute path that works when the page is opened from disk but names the reader's folders
    (don't publish such a page as is). Wiki links search the document's folder, then the root,
    never through a symbolic link. Links to pages stay `.md` in `--output` (no rewrite to
    `.html`: mdv renders one file per run and doesn't know where the others will go).
  - Diagnostics (#65) go to standard error only: frontmatter `mdv:` keys a render ignored are
    always reported as `mdv: <input>: warning: <reason>` (exit status unchanged), and
    `--verbose` adds the flavor and wiki link setting used and where each came from (flag,
    document, default). Control characters from the document are printed as `\u{XX}`, so
    frontmatter can't send escape sequences to the terminal.
  - Custom preprocessor (#66, `PreprocessorOptions`, help section "Preprocessor"): **only
    `--preprocessor PATH` runs one**, with repeatable `--preprocessor-arg ARG` (taken verbatim,
    even when it starts with `-`). Headless output of an untrusted file never starts a program
    implicitly, so the app's Settings > Markdown preprocessor is not read (no
    `--app-preprocessor`: the same command gives the same output whatever the app is set to).
    PATH is a file path, made absolute against the working directory and checked by
    `PreprocessorConfiguration`; it is never looked up on `PATH`. Same runner, contract, and
    limits as the app (`PreprocessorLimits.standard`; `CLIEnvironment.preprocessorLimits` for
    tests). A file passes `documentURL` (`MDV_DOCUMENT_PATH`, its folder as working directory);
    standard input passes `nil` and runs in `/`, as in the app, not in the shell's folder. HTML
    output only, like the Rendering flags (usage error otherwise). **A failure fails the run**:
    exit 70 (`EX_SOFTWARE`) with `mdv: <input>: <PreprocessorError.message>` (including the
    quarantine hint) and the stderr tail on the following lines (control characters escaped,
    tabs and line breaks kept), and no HTML; there is no `--preprocessor-fallback`. The
    script runs in its own process group, so a terminal's Ctrl-C doesn't reach it: while it
    runs, `InterruptCancellation` turns `SIGINT`, `SIGTERM`, and `SIGHUP` into cancellation
    (the runner stops the group and reaps it), then restores the default action and re-raises
    the signal, so mdv dies of it as shells expect. A signal mdv started out ignoring (`nohup`,
    background jobs) stays ignored. Only installed around the run, so reading standard input
    is still interrupted the default way.
  - CLI to app (#67, `WorkspaceAppOpener`, `AppOpenEvent` in MdvCore, `DocumentOpener` in the
    app): `mdv FILE` checks every path first (missing, folder, unreadable: exit 66, nothing
    opens; relative paths resolve against the shell's folder) and `--theme` (`ThemeResolver`,
    as for `--html`), then builds a standard **Open Documents Apple Event** (`aevt/odoc`, the
    files as its direct object) with mdv's own optional parameters (`mdvT`: theme id) and hands
    it to Launch Services as `NSWorkspace.OpenConfiguration.appleEvent`
    (`openApplication(at:)`). Launch Services launches the app with it as the first event, or
    sends it to the running app, and activates the app: Finder's path, so no Automation
    (TCC) prompt, and the app opens files exactly as from Finder. AppKit handles Open
    Documents events itself and never calls the delegate's `application(_:open:)` for mdv's
    document types (Launch Services launch or running app, `open -a`, Finder), so
    `DocumentController.openDocument(withContentsOf:display:completionHandler:)` applies them
    (`DocumentOpener.openForOpenDocumentsEvent`). While an earlier open is in flight AppKit
    opens an event's files later, when `NSAppleEventManager.currentAppleEvent` is no longer
    the event, so `OpenDocumentsEventTap` (an Apple Event Manager handler for `aevt/odoc`
    that records the event and passes it on to AppKit's) keeps each event's parameters by
    file in `OpenDocumentsEventLog` (taken once per file, gone after 30 s).
    (`application(_:open:)` was the first design; it lost `--theme` and `--wait` on every
    Launch Services path, which CI's single copy caught.) Rejected: `open -b`
    (no way to pass options, errors were its exit status), launch arguments (launch only), a
    URL scheme (a web page could trigger it), XPC (needs a launchd service).
    - Finding the app: the app that contains the executable (`mdv.app/Contents/Helpers/mdv`,
      symlinks resolved, bundle id checked), so a development build's CLI opens that build; run
      outside a bundle (`swift run mdv`), the app Launch Services knows by bundle id; neither:
      exit 69. Launch Services finds a *running* app by bundle id, not path, so with another
      copy running (an installed mdv next to a dev build) the CLI launches its own copy as a
      new instance, or, if its copy is running too, sends that process the event directly.
      Directly sent `odoc` events reach AppKit's scripting handler, not the delegate, and lose
      the parameters, so the direct path uses mdv's own class `mdv /odoc` (same direct object
      and parameters; `AppDelegate.handleDirectOpen`). The direct path is also the fallback
      when Launch Services refuses a sandboxed caller (the UI test runner, whose children
      inherit its sandbox; `AppUITests.entitlements` allows its Apple Events to mdv).
    - **Trust model:** any local process can already send the app these events, with any
      parameters, so they are presentation-only and validated as untrusted input:
      `AppOpenParameters(event:)` keeps a theme id only if it is UTF-8/UTF-16 text of at most
      1 KB, 1–256 characters, no control/format characters or surrounding whitespace; the app
      then uses it only if it is registered or a `custom:` id (which shows Settings' default
      until its file loads). The direct event's files are `typeFileURL` items only (text is
      never coerced into a path), at most 1000. Nothing widens what a document can do; files
      open with the same checks as from Finder.
    - `--theme` becomes each window's View > Theme pick (beats `mdv.theme`; restoration
      keeps it), set before a new window first shows; an already-open window switches. An
      already-open file focuses its window (`DocumentController` finds it by identity).
      `--flavor` without `--html`/`--fragment`/`--output` is a usage error (64): windows have
      no per-window flavor (M4); Settings > Markdown and `mdv.flavor` decide. `mdv FILE`
      activates the app, like `open`; no `--background` until someone needs it.
    - Further parameters go on the same event (`mdvW`, the `--wait` token, #69), read by
      `AppOpenParameters` with the same size and type checks. (`mdvI` was reserved for
      standard input; #68 needed no parameter.) Timing: `MDV_LAUNCH_TIMING` and
      `MDV_LAUNCH_TIMING_LOG` are the only environment the CLI passes to an app it launches
      (`scripts/measure-cold-open -c`).
  - Standard input into a window (#68, `cmd | mdv`, `StandardInputHandoff` in MdvCore):
    - **Transport: a private handoff file the app deletes once it has read it.** The CLI
      writes the Markdown to `$TMPDIR/mdv-stdin.XXXXXXXX/stdin.md` (`mkdtemp(3)`: an
      unpredictable name, created exclusively, mode 0700; the file `O_EXCL|O_NOFOLLOW`, mode
      0600; `TMPDIR` when absolute, else Foundation's temp folder; a shared `/tmp` is still
      safe) and puts it last in the Open Documents event's direct object. The app's
      `DocumentController.openDocument(withContentsOf:display:completionHandler:)` recognizes
      it, reads it, deletes it and its folder right away, and returns an untitled document;
      if the event never reached the app, the CLI deletes it. Recognizing the file there, by
      its shape, rather than by an event parameter (`mdvI`, reserved by #67) works on every
      path an Open Documents event takes: a cold launch while another copy with the bundle id
      runs (Launch Services' new instance) gets the event through AppKit's own handler, which
      never calls the delegate and drops mdv's parameters (seen while building #68; the same
      launch loses `--theme`). A parameter would add no trust either: any sender can set it.
      Rejected: the bytes in an event parameter. An Open Documents event with no files never
      reaches `application(_:open:)`, and Launch Services rewrites custom event classes, so
      bytes could only go by the direct `mdv /odoc` path, which needs the app already
      running; two transports weren't worth it. A file is left behind only when the app dies
      between the CLI's send and its read (the system cleans its temp folder).
    - **Trust model:** any local process can send that event naming any file, so the app
      deletes only a file it verifies is a handoff, through descriptors, without following
      links: a folder named `mdv-stdin.*` owned by this user with no group/other permissions,
      holding a regular file named `stdin.md`, owned by this user, no group/other
      permissions, one link (not a hard link to another file); it is read through the checked
      descriptor. Anything else, `stdin.md` files included, is left alone and opens as an
      ordinary file. The checks are on shape, not location (a sandboxed caller's temp folder
      is its container), so a sender (or a Finder open, a drop) can at worst make the app
      read and delete a file with that exact shape, which only mdv makes, and which a
      same-user process could delete anyway.
    - **Limits:** at most 10 MB (`StandardInputHandoff.maximumBytes`, the preprocessor's input
      bound, twice the largest measured document). The CLI reads no more than that plus a
      byte (`yes | mdv` ends), and refuses more (65), empty or whitespace-only input (66), and
      non-UTF-8 (65), with nothing opened. The app checks size and UTF-8 again (a hand-made
      handoff), deletes it, and presents the error. `--html` keeps reading standard input
      without a limit. No streaming: input is read to EOF (`tail -f log.md | mdv` never opens;
      deferred).
    - **The window:** `MarkdownDocument(standardInput:)`, an untitled document with no file:
      titled from its frontmatter `title` or first heading, else "Standard Input"; no live
      reload, nothing in Open Recent, and its window isn't restorable (nothing to reopen).
      Settings > Markdown, `mdv:` frontmatter, and `--theme` apply as to any document; wiki
      links have no resolver (page links show as missing), and the custom preprocessor, if on,
      runs with no document path, in `/`, as in the CLI. **No allowed root:** the page has no
      base URL, so relative images don't load (a broken image, as for any image outside a
      root) and relative links go nowhere; the shell's folder isn't used, because piped text
      (`curl … | mdv`) shouldn't read local files by where the shell happens to be.
    - `-` mixes standard input with files (`mdv a.md - b.md`): the files open, then standard
      input's window (`AppOpenRequest` keeps them apart). `cmd | mdv --wait` waits for the
      standard input window like any other (it joins the token in `DocumentOpener`).
  - Completions and man page (#71): **generated from the ArgumentParser command, never
    committed**, so a new flag appears in both with no extra step. zsh, bash, and fish scripts
    are ArgumentParser's (`--generate-completion-script`). FILE, `--output`, and
    `--preprocessor` complete paths (`completion: .file()`), `--flavor` the bundled ids, and
    `--theme` the ids `--list-themes` prints, computed when Tab is pressed
    (`ThemeFlavorOptions.completionThemeIDs`, `.custom`), so a new custom theme completes
    without regenerating the script; `custom:` ids are escaped for zsh's `_describe`. The man
    page is ArgumentParser's `generate-manual` plugin output (NAME, SYNOPSIS, the option
    list) finished by `ManualPage` (run by the `MdvManualTool` build tool): DESCRIPTION's
    overview, ENVIRONMENT, FILES, EXIT STATUS, EXAMPLES, and SECURITY CONSIDERATIONS are built
    from `HelpText`, `ExitStatus.entries`, `ThemeResolver`, and `PreprocessorLimits`, the same
    values `--help` uses. `make cli-docs` (`scripts/generate-cli-docs`) writes both to
    `build/cli-docs`; `make test-core` runs it first and checks that every option in
    `--experimental-dump-help` is in the page and each script, and that `mandoc -T lint`
    passes. The app build copies them into `Contents/Resources/man/man1/mdv.1` and
    `Contents/Resources/completions/` (`_mdv`, `mdv.bash`, `mdv.fish`; project.yml script
    phase; Release fails without the man page), for the Homebrew cask and Install Command Line
    Tool, which links the man page into `share/man/man1` beside the command's folder (where
    `man` looks for a `bin` on `PATH`). Completions aren't installed by the app: a shell's
    setup is the reader's, so the success alert and README point at the scripts instead.
    - `--wait` (#69, `WindowsClosedWaiter` in the CLI, `WindowWaits` in the app): the CLI
      makes a random token per invocation (a version 4 UUID), registers for the Darwin
      notification `com.itspriddle.mdv.windowsClosed.<token>` (`notify(3)`: delivered on a
      dispatch queue, no run loop, works from the sandboxed UI test runner), then sends the
      open event with the token as `mdvW`. The app tracks the windows each token opened or
      brought forward (**an already-open file's window counts**; a tab is a window; a window
      whose file was deleted stays open, so it still counts), and posts the notification once
      the event has finished opening and none of them is left open (every file failing posts
      at once). Two `--wait`s on one file both end when its window closes. Quitting posts every
      token. The CLI also watches the app's process (`DispatchSource` process exit, from the
      pid Launch Services or the direct path reports), so a crash or force quit ends the wait;
      either way mdv exits 0. Ctrl-C keeps its default action: mdv dies of `SIGINT` (130) and
      the windows stay open. Tokens aren't saved: restored windows wait for no one.
      **Trust model:** any process can post any Darwin notification, so a forged one can only
      end a wait early; the app accepts only a well-formed UUID (exactly 36 characters of
      text), so a forged token can only make it post a name under mdv's prefix when windows
      close. Nothing in the app acts on a notification. Rejected: holding the open event's
      reply until close (Launch Services gives no reply), XPC/Mach services (need a launchd
      job), `NSDistributedNotificationCenter` (needs a run loop the async CLI doesn't run).
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
    images when the page is opened. `--block-remote-images` (#65) writes placeholders instead.
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
  only checks; `//host` stays remote. Copy as HTML and `mdv --html` of standard input keep them
  as written; `mdv --html FILE` rewrites them against the file's root, as the app does (#65).
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
  - **No `--no-sanitize` (#65).** The CLI has no way to turn sanitizing off. Headless output is
    a page meant to be opened in a browser, where page JavaScript isn't disabled as it is in
    the viewer, so passing raw HTML from an untrusted file through would run its scripts
    (and the page's CSP is the only other guard). The spec suites turn it off in MdvCore
    (`RenderOptions.spec`), which is where unsanitized output belongs.
  - **The CLI doesn't read Settings > Markdown (#65)**: its output depends only on its flags
    and the file, never on app state. Frontmatter overrides apply as in the app, under the
    same rules (presentation only); `--flavor` and `--wiki-links`/`--no-wiki-links` beat them.
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
- **Documents can't raise their own privileges (#54).** Frontmatter overrides choose among
  presentation options only: `flavor` (a registered flavor), `theme`, and `wikilinks`. There is
  no generic mapping from frontmatter keys to `RenderOptions`; `RenderOptions.applying(_:)`
  changes the flavor (and #53's wiki links toggle) and nothing else, so sanitizing, the remote
  image policy, `linkRoot`, source lines, and every other setting stay as the reader's app set
  them. The custom preprocessor isn't a render option at all: it is configured only in Settings
  and runs before frontmatter is read. Any other key under `mdv:` (`sanitize`, `remoteImages`,
  `preprocessor`, ...) is ignored and reported; unregistered flavors (such as the spec suite's)
  can't be chosen; a theme id is only looked up in the registry, never read as a path. Tests
  (`DocumentOverridesSecurityTests`) render a document that tries each of these.
- Custom preprocessor scripts run only when the user configures them (#57), and they are the
  first stage of the render pipeline (#51), so their output is still parsed, transformed, and
  sanitized like any file.
  - **Opt-in (#57):** off by default. Settings > Markdown > Custom preprocessor is the only
    way to turn it on (`CustomPreprocessorSettings`): the program is chosen with an Open panel
    (never a typed path; links are kept as chosen, not resolved) and stored as an absolute path,
    a choice that isn't an executable file is refused with the reason, and the toggle turns it
    on only after a warning that mdv will run that program on every document it opens, as the
    reader, with the reader's access. Arguments are a list of fields, passed verbatim (empty
    ones dropped). Frontmatter can't turn it on, choose a program, or pass arguments (tested,
    `CustomPreprocessorTests.frontmatterCantEnable`), and the only launch argument for it,
    `-MdvUITestPreprocessor`, is compiled into Debug UI-test builds only (as is
    `-MdvUITestRenderDelay`, which holds up renders so UI tests can see the progress indicator). UI tests and hosted
    tests keep the setting in memory.
  - **Which documents:** every document the app opens while it is on; no extension filter
    (mdv only opens Markdown and plain text, and a script can check `MDV_DOCUMENT_PATH` and pass
    a file through unchanged). The file must still be UTF-8 (the open fails otherwise, as
    without a preprocessor), and the script gets its exact bytes. `mdv --html` runs one only
    when `--preprocessor PATH` names it (#66; the CLI bullets under Architecture).
  - **Failures render the document without it, plus a bar** (`PreprocessorFailureBar`), never an
    alert and never an error page: "Preprocessor failed", the reason (`PreprocessorError.message`),
    and a Show Details disclosure with the stderr tail, shown verbatim. A program that was
    deleted or lost its execute bit is such a failure, not a silent unprocessed render. When
    macOS refuses to start a program that passed the executable check (`EPERM` or `EACCES` from
    `posix_spawn`), the reason adds a likely cause without claiming it (#59): the file may be
    quarantined (downloaded, or saved by a sandboxed app), with `xattr -d com.apple.quarantine`
    and System Settings > Privacy & Security as the fixes to try. Seen with scripts the
    sandboxed UI test runner writes; not reproduced with a quarantined script run from a
    terminal, so the cause isn't confirmed for downloads.
    Settings shows the last run of the session (succeeded, or failed and why) instead of a "Test
    on…" button: opening a document is the test, and its window says what went wrong.
  - **Lifecycle:** the first render of an open waits for the script (up to the 5.5 s worst
    case; the window shows its blank, theme-colored page meanwhile, with the progress indicator
    after 300 ms, #58). Each live reload runs it
    again off the main actor. A newer render, `setContent`, a newer reload, or closing the
    document cancels the run in flight, which stops its process group. Turning it off, or
    changing the program or arguments, re-renders open documents in place; a render or reload
    still running with the old setting starts over at once rather than waiting for the script.
  - **Stress suite** (`StressTests+Preprocessor`, `+Markdown`): windows over scripts that hang,
    crash, flood stdout, or leave children; reload storms; windows closed mid-run; one script
    switching between hanging, crashing, flooding, and failing as live reload changes the file,
    with its settings changing mid-run (#59). The main thread doesn't stall and no process
    (script, child, or zombie) is left. The suite passes under the Address and Thread
    Sanitizers (M4 close-out).

  The runner is `CustomPreprocessor` in `MdvCore` (#56):
  - **Contract:** the document's bytes on stdin, Markdown as UTF-8 on stdout, exit status 0
    for success. Output that isn't UTF-8 or contains a NUL byte is an error. A non-zero exit
    discards stdout.
  - **Executable:** an absolute path, standardized and stored as given. It is never looked up
    on `PATH`. Symbolic links are followed only to check the target, so a Homebrew upgrade
    that moves the target keeps working. It must exist, be a regular file, and be executable
    by the user, checked when configured and again before every run.
  - **Arguments:** a fixed list from configuration, passed as an argv array to `posix_spawn`:
    no shell, no expansion. Nothing from the document is ever added to the command line. The
    document's path goes in `MDV_DOCUMENT_PATH`, never as an argument that could be read as an
    option.
  - **Environment:** only `PATH` (fixed:
    `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, the same from Finder or a
    terminal), `HOME`, `TMPDIR`, `LANG=en_US.UTF-8`, and `MDV_DOCUMENT_PATH` (when there is a
    file). None of the app's own environment is passed on.
  - **Working directory:** the document's folder, so relative paths mean what they mean to the
    reader. With no file (piped input), it is `/`.
  - **Descriptors and signals:** the child gets only the three pipes
    (`POSIX_SPAWN_CLOEXEC_DEFAULT`) and default signal handling. mdv's stdin pipe has
    `F_SETNOSIGPIPE`, so a script that closes stdin can't raise `SIGPIPE` in mdv.
  - **Limits** (`PreprocessorLimits.standard`): 5 s wall clock, 10 MB of input (a larger
    document doesn't run), 10 MB of stdout, and the last 64 KB of stderr kept for the error
    message. More stderr is drained and dropped.
  - **Stopping:** the script runs in its own process group. On timeout, too much output, or
    cancellation (a newer render cancels the task), the whole group gets `SIGTERM`, then
    `SIGKILL` after a 0.5 s grace period, so children it started die too. When the script
    exits on its own, anything left in its group is stopped the same way. The script is reaped
    only after the group's final `SIGKILL`, so its group id can't be reused by another process
    in the meantime.
  - **No deadlocks, no blocked threads:** one kqueue loop on a dedicated thread (never the
    Swift cooperative pool) writes stdin and reads stdout and stderr together. It also watches
    for the exit, the deadline, and cancellation. A script that never reads stdin, or fills a
    pipe, can't stall mdv. The worst case is the timeout plus the grace period.
  - **Failures** are a typed `PreprocessorError`: input too large, executable unusable, launch
    failed, timed out, output too large, exit status, signal, not UTF-8, or NUL, each with a
    user-presentable message and the stderr tail. Each failure is logged with `os.Logger`.
  - **Not a sandbox:** the script runs as the user, with the user's file access. A process that
    leaves the group (`setsid`) is out of reach, though mdv stops reading its pipes after the
    grace period. Opting in means trusting the executable.
- **Install Command Line Tool (#70)** writes outside the app, sometimes as root, so it follows
  narrow rules (`CommandLineToolInstaller`, unit tested over temp folders):
  - It only ever creates, replaces, or removes a symbolic link named `mdv` whose absolute
    destination is `<X>.app/Contents/Helpers/mdv`, where `X.app` is gone (a moved app) or has
    mdv's bundle identifier. A file, a folder, a relative link, or a link anywhere else
    (including into another app with the same layout) is shown to the reader and left alone,
    by install and by uninstall. The man page (#71) follows the same rule as a second item:
    a link named `mdv.1` in `share/man/man1` beside the command's folder, to
    `<X>.app/Contents/Resources/man/man1/mdv.1`. It goes along only when this copy has one and
    nothing foreign is at its path (a page that isn't ours is skipped silently, not shown),
    and is removed with the command when it is ours. Both go in one batch: every path is
    checked before anything changes, and the links needing an administrator share one
    privileged run (the scripts take argument triples or pairs and check them all first).
  - Links are made atomically: a temporary link beside the target is renamed into place, with
    `RENAME_EXCL` when nothing was there. A replace or removal re-reads the link first and
    stops if its destination changed.
  - `~/.local/bin` needs no privileges. For a folder the reader can't write (`/usr/local/bin`),
    mdv uses AppleScript's `do shell script … with administrator privileges` (not the deprecated
    `AuthorizationExecuteWithPrivileges`; a privileged helper tool is out of proportion for one
    link). Nothing is interpolated into code: the AppleScript source is a constant whose
    handler receives the shell script and its arguments as Apple event parameters and quotes
    each with `quoted form of`. The shell scripts are constants too
    (`privilegedInstallScript`, `privilegedUninstallScript`) and get the paths only as `$1`…,
    which must be absolute and NUL-free. Run as root, they repeat the ownership check (the
    link must still have the destination mdv read, and not resolve to a folder) and exit 3
    otherwise. Tests run the same scripts, and the same AppleScript handler minus the
    privilege clause, over paths full of quotes, `$(…)`, backticks, and newlines.
  - The only launch argument, `-MdvUITestCommandLineToolFolder`, is Debug-only; UI-test and
    hosted unit-test launches without it offer no folders, so tests never touch
    `/usr/local/bin` or `~/.local/bin`.
  - To choose the default folder, mdv reads the reader's `PATH` from their login shell
    (`$SHELL -l -c`, 2 s limit, no input): the reader's own configuration, nothing from a document.
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
