# Roadmap

Milestones are ordered by dependency. Each one becomes a GitHub milestone, then gets broken down
into issues in its own planning session. Scope lists are starting points, not contracts. Refine
them when the milestone is broken down.

| Milestone                               | Theme                          | Release   | Status |
| --------------------------------------- | ------------------------------ | --------- | ------ |
| [M0](#m0-foundation)                    | Foundation                     | -         | Done   |
| [M1](#m1-core-rendering)                | Core rendering                 | -         |        |
| [M2](#m2-viewer-app)                    | Viewer app                     | -         |        |
| [M3](#m3-themes)                        | Themes                         | -         |        |
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
- Syntax highlighting for fenced code blocks. **Decided:** native, at render time: bundled
  highlight.js in JavaScriptCore inside `MdvCore` (works for `--html` output, no JS in the viewer)
- Source line annotations (`data-source-line`) to enable scroll sync later
- Golden/snapshot test corpus (CommonMark spec, GFM spec samples, real-world READMEs)

**Exit criteria:** GFM spec examples pass (or have documented exceptions); a representative
corpus of READMEs renders to match GitHub; renderer is fuzz/stress tested on large inputs.

## M2: Viewer app

A pleasant, Mac-native document viewer.

- Open via Finder, Open dialog, drag and drop, recents, Dock; tabs; window restoration
- Offer to become the default `.md` handler
- Live reload on file change (FSEvents/`DispatchSource`), preserving scroll position
- Relative images and links resolve against the file (`loadFileURL` with read access scoped
  to the document's folder)
- Link handling: local `.md` opens in mdv, anchors scroll, external URLs open in the browser
- Find in page, zoom (Cmd +/-/0), print, copy as HTML / Markdown source
- Outline / table-of-contents sidebar from headings
- Light/dark appearance following the system
- UI tests for the core flows

**Exit criteria:** daily-drivable for reading local docs; no known crashes; UI tests in CI.

## M3: Themes

CSS themes as a first-class feature.

- Bundled themes: GitHub (Primer, light and dark), Google Docs-style, minimal/serif
- Theme model in `MdvCore`: name, stylesheet(s), light/dark variants, optional print CSS
- Custom themes: CSS files in `~/Library/Application Support/mdv/Themes`, hot-reloaded
- Theme picker per window plus a global default in a Settings window
- Font size and content width controls layered on top of any theme
- Theme authoring guide (the only doc written for end users before 1.0)

**Exit criteria:** switching themes is instant; a custom CSS file appears and updates without
restart; bundled themes pass a visual regression check.

## M4: Flavors and preprocessors

Control how source becomes Markdown.

- Flavor presets: CommonMark (strict), GFM (default), plus room for others; each a defined set of
  parser options and AST transforms
- Built-in preprocessors (e.g. frontmatter stripping, wiki-links `[[Page]]`, include/transclusion
  TBD)
- Custom preprocessor: user-configured executable, document on stdin, Markdown on stdout,
  timeout and size limits, explicit opt-in with a clear warning
- Per-document overrides via frontmatter (`mdv: { flavor: commonmark, theme: github }`)
- Settings UI for flavors and preprocessors

**Exit criteria:** each flavor has its own test corpus; a misbehaving script (hang, crash,
huge output) cannot hang or crash the app.

## M5: CLI

Make the terminal workflow excellent.

- `mdv FILE...` opens files in the running app (or launches it)
- `cmd | mdv` streams stdin into a new window without leaving files behind in temp
  directories longer than needed
- `--theme NAME`, `--flavor NAME`, `--html` / `--output FILE`, `--standalone` (inline CSS)
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
   following [Conventional Commits](https://www.conventionalcommits.org).
3. **Merge:** PR with tests; CI (`make lint`, core tests, app build/tests) must be green.
4. **Close out:** update this roadmap (check off scope, adjust later milestones), then plan the
   next milestone.
