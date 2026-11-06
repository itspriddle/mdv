# README corpus

Real-world READMEs and docs, run by `GitHubCorpusTests` (`make test-core`). Each `NAME.md` is
rendered with the default `RenderOptions` and:

- compared with `NAME.github.html`, github.com's rendering of the same file, after normalizing
  both sides; every remaining difference is an exception in `corpus.json`, with a reason;
- compared byte for byte with `NAME.mdv.html`, a snapshot of mdv's own output, so any change to
  the output shows up as a diff.

## Sources

Permissively licensed files only, copied verbatim at a pinned commit. `corpus.json` records each
file's source URL, commit, and license; the table summarizes them.

| File                    | Source                                                   | License           | Covers                                            |
| ----------------------- | -------------------------------------------------------- | ----------------- | ------------------------------------------------- |
| `awesome`               | `sindresorhus/awesome` `readme.md`                       | CC0-1.0           | HTML-heavy header, `<picture>`, long nested lists |
| `bat`                   | `sharkdp/bat` `README.md`                                | MIT OR Apache-2.0 | Badges, tables, many shell blocks, alerts         |
| `deno`                  | `denoland/deno` `README.md`                              | MIT               | Reference-style badges, raw `<img>`, ts/sh/ps1    |
| `emoji-cheat-sheet`     | `ikatyang/emoji-cheat-sheet` `README.md`                 | MIT               | ~1,800 emoji shortcodes in large tables           |
| `fzf`                   | `junegunn/fzf` `README.md`                               | MIT               | `<details>`, tables, bash/fish/nu/vim, alerts     |
| `httpie`                | `httpie/cli` `README.md`                                 | BSD-3-Clause      | Centered HTML header, badges                      |
| `jekyll-front-matter`   | `jekyll/jekyll` `docs/_docs/front-matter.md`             | MIT               | YAML frontmatter, raw HTML tables, liquid/yaml    |
| `kep-template`          | `kubernetes/enhancements` `keps/NNNN-kep-template/…`     | Apache-2.0        | Nested task lists, HTML comments, TOC             |
| `next-js`               | `vercel/next.js` `readme.md`                             | MIT               | `<picture>` header, badges                        |
| `node`                  | `nodejs/node` `README.md`                                | MIT               | Long nested lists, links, code                    |
| `rust-blog-1-82`        | `rust-lang/blog.rust-lang.org` `content/Rust-1.82.0.md`  | MIT OR Apache-2.0 | TOML frontmatter, rust/asm/diff code              |
| `rust-rfc-3559`         | `rust-lang/rfcs` `text/3559-rust-has-provenance.md`      | MIT OR Apache-2.0 | Footnotes, rust code                              |
| `swift-argument-parser` | `apple/swift-argument-parser` `README.md`                | Apache-2.0        | Swift code                                        |
| `vscode`                | `microsoft/vscode` `README.md`                           | MIT               | Simple README, user-attachment image              |

To add a file: copy it unmodified, add its entry to `corpus.json`, run
`scripts/update-github-fixtures NAME`, then
`MDV_RECORD_SNAPSHOTS=1 swift test --filter GitHubCorpusTests` and review the diff.

## GitHub reference

`scripts/update-github-fixtures` (run manually; needs `gh` auth and network, not run in CI)
checks that `NAME.md` is the file at the recorded commit, then saves github.com's file view of
it: `GET /repos/OWNER/REPO/contents/PATH?ref=COMMIT` with
`Accept: application/vnd.github.html`. That is exactly what a README reader sees. Neither
`POST /markdown` mode matches it: `mode=gfm` (comments) turns soft line breaks into `<br>` and
writes no heading ids, and `mode=markdown` writes no task lists and older footnote markup.

## Normalization

Both sides go through `HTMLNormalizer` (the spec suite's port of cmark's `normalize.py`) after
`CorpusNormalizer` removes the differences that are deliberate and apply to every document:

| GitHub output                                                         | Normalized to / why mdv differs                                     |
| --------------------------------------------------------------------- | ------------------------------------------------------------------- |
| File-view wrapper `div`/`article`, `dir="auto"` on blocks             | Removed; github.com page markup                                     |
| `<div class="markdown-heading">`, id on a trailing octicon anchor     | `<hN id="slug">`; mdv's empty anchor link is removed on its side    |
| `<div class="highlight …"><pre>` with `pl-` spans; copy-button `div`s | `<pre><code>`; all spans in `pre` dropped (mdv: `hljs-`)            |
| Trailing newline trimmed from code, newline after raw `<pre>` dropped | Same on both sides (equivalent in a browser)                        |
| `"` literal in text; `&nbsp;` as a character                          | `&quot;` and `&nbsp;` decoded on both sides                         |
| Image links, camo proxy URLs, `style` on images, `data-animated-image`| Unwrapped / original URL; github.com image handling                 |
| Signed `private-user-images` URLs                                     | The `user-attachments` URL from the source (the signature expires)  |
| `<themed-picture>`, `<markdown-accessiblity-table>`, `role="table"`   | Removed; github.com custom elements                                 |
| `<g-emoji>` wrapper; custom emoji (`:octocat:`) as remote images      | Bare emoji; the shortcode (mdv loads no remote content)             |
| `user-content-` prefixes, footnote id nonces, `rel="nofollow"`, `notranslate`, `id=""`, hovercard attributes | Removed (see `Fixtures/github/README.md`) |
| Bare issue URL shortened to an `#123` issue link                      | Link with the URL as text, as mdv renders it                        |
| Leading YAML frontmatter table                                        | Removed; mdv hides frontmatter by default                           |
| Alerts (`> [!NOTE]`) as `markdown-alert` divs                         | The block quote mdv renders (alerts are not supported yet)          |

`MDV_CORPUS_DIFF_DIR=/some/dir` makes the test write both normalized outputs there.

## Exceptions

What remains is listed per file in `corpus.json`: a snippet of GitHub's normalized output (it
must occur exactly once) and what mdv renders instead. A stale exception fails the test. The
kinds, all deliberate or deferred:

- **HTML tree construction** (`awesome`, `jekyll-front-matter`): GitHub re-parses its output with
  an HTML5 parser, which closes an open `<p>` before a block and moves misnested tags. mdv keeps
  the raw HTML's structure; a browser builds the same DOM from it.
- **Top-level raw `<img>`** (`deno`, `fzf`): github.com wraps it in a paragraph and adds a default
  `<summary>` to a `<details>` without one.
- **Alert marker case** (`bat`): `[!tip]` in the source; the normalizer writes `[!TIP]`.
- **TOML frontmatter** (`rust-blog-1-82`): github.com renders `+++` blocks as text; mdv hides them.
