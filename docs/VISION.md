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
3. **Themeable with plain CSS.** Bundled themes (GitHub Primer, Google Docs-style, minimal) are
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
 file / stdin ──► Preprocessors ──► MdvCore renderer ──► HTMLDocument ──► WKWebView
                  (frontmatter,      (swift-cmark →        (theme CSS,      (app window,
                   built-in, user     MarkdownNode AST →    CSP, base URL)   print/PDF)
                   script)            HTMLRenderer)
                                                └──────► stdout (mdv --html)
```

- **MdvCore** (Swift package): parsing, AST transforms, HTML rendering, frontmatter, themes,
  preprocessors. No UI dependencies; tested with `swift test`.
- **Parsing:** [`swiftlang/swift-cmark`](https://github.com/swiftlang/swift-cmark) (cmark-gfm, the
  engine GitHub uses), called directly through its C API. `MarkdownParser` enables GFM extensions
  and footnotes per `RenderOptions`, never enables smart punctuation, and copies cmark's tree into
  our own `Sendable` `MarkdownNode` AST; no C pointers outlive a parse.
- **Rendering:** `HTMLRenderer` walks the `MarkdownNode` AST and emits HTML (cmark-compatible for
  CommonMark). Owning the AST and the output is what lets us control heading anchors, task lists,
  emoji, raw HTML sanitizing, syntax highlighting, and source-line mapping, and gives M4
  transforms one tree to operate on.
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
  public API, what a viewer needs and `DocumentGroup` hides: `NSFilePresenter` change
  notifications and revert for live reload, per-window state restoration, tabs, recents, the
  responder chain for menu commands, and a window controller to own the web view. SwiftUI stays
  for window content (sidebar, find bar, banners).
- **Default handler:** mdv declares Markdown with `LSHandlerRank: Alternate` and asks, never
  grabs (#23). `Owner` claims a type mdv doesn't define and `Default` lets Launch Services pick
  mdv without asking; both take the choice away from the user. Instead mdv offers once, in a
  non-modal panel, when a document opens while another app is the default ("Not Now" snoozes
  30 days, "Don't Ask Again" is permanent), and the app menu has "Make mdv the Default Markdown
  Viewer" until Settings exists (M3). Plain text stays `None`.
- **CLI:** Swift ArgumentParser tool embedded in the app bundle (`Contents/Helpers/mdv`),
  symlinked onto `PATH` from the app.
- **Tooling:** XcodeGen (`project.yml`), SwiftLint, swift-format, Swift Testing, GitHub Actions.
- **Distribution:** Developer ID signing, notarization, Sparkle 2, Homebrew cask.

## Security model

- The rendered page has a strict Content-Security-Policy: no remote loads, inline styles only,
  local/`data:` images only. Remote images become an explicit, per-document opt-in. In the app
  it is `default-src 'none'; style-src 'unsafe-inline'; img-src mdv-doc: data:;`; `mdv --html`
  output keeps `img-src file: data:` so a saved page still shows the images beside it.
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
- Links open in the default browser; local Markdown links open in mdv; nothing navigates the
  viewer away from the document.
- Custom preprocessor scripts run only when the user configures them, with a timeout, no shell
  interpolation, and the document passed via stdin.
- Hardened runtime, notarized builds, Sparkle updates signed with EdDSA over HTTPS.

## Success looks like

- `mdv README.md` shows a document indistinguishable from GitHub's rendering in under 200 ms.
- Switching themes or editing the file in another app updates the window instantly.
- A new contributor can clone, `make bootstrap && make test`, and be productive in minutes.
