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
                  (frontmatter,      (swift-markdown       (theme CSS,      (app window,
                   built-in, user     AST → HTML via        CSP, base URL)   print/PDF)
                   script)            MarkupVisitor)
                                                └──────► stdout (mdv --html)
```

- **MdvCore** (Swift package): parsing, AST transforms, HTML rendering, frontmatter, themes,
  preprocessors. No UI dependencies; tested with `swift test`.
- **Parsing:** [`swiftlang/swift-markdown`](https://github.com/swiftlang/swift-markdown), backed by
  Apple's `swift-cmark` GFM fork. We own the HTML output via a custom `MarkupVisitor` so we control
  heading anchors, task lists, emoji, raw HTML handling, and source-line mapping.
- **Display:** `WKWebView`. HTML + CSS is what makes CSS themes, print styles, and PDF export
  possible; SwiftUI-native renderers (e.g. Textual, MarkdownView) can't use stylesheets.
- **App:** SwiftUI `DocumentGroup` in viewer mode, AppKit where SwiftUI falls short.
- **CLI:** Swift ArgumentParser tool embedded in the app bundle (`Contents/Helpers/mdv`),
  symlinked onto `PATH` from the app.
- **Tooling:** XcodeGen (`project.yml`), SwiftLint, swift-format, Swift Testing, GitHub Actions.
- **Distribution:** Developer ID signing, notarization, Sparkle 2, Homebrew cask.

## Security model

- The rendered page has a strict Content-Security-Policy: no remote loads, inline styles only,
  local/`data:` images only. Remote images become an explicit, per-document opt-in.
- JavaScript is disabled in the viewer until a feature needs it; when enabled, only scripts
  shipped in the app bundle may run, never script from the document.
- Raw HTML in Markdown is sanitized per a defined policy rather than passed through blindly.
- Links open in the default browser; local Markdown links open in mdv; nothing navigates the
  viewer away from the document.
- Custom preprocessor scripts run only when the user configures them, with a timeout, no shell
  interpolation, and the document passed via stdin.
- Hardened runtime, notarized builds, Sparkle updates signed with EdDSA over HTTPS.

## Success looks like

- `mdv README.md` shows a document indistinguishable from GitHub's rendering in under 200 ms.
- Switching themes or editing the file in another app updates the window instantly.
- A new contributor can clone, `make bootstrap && make test`, and be productive in minutes.
