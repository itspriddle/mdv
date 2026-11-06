# GitHub reference fixtures

Run by `GitHubFixtureTests` (`make test-core`): each `NAME.md` is rendered with the default
`RenderOptions` (GFM, GitHub markup) and compared with `NAME.html`, GitHub's own rendering.

## Capturing

`NAME.html` is the unmodified output of GitHub's Markdown API:

```sh
gh api markdown -f mode=gfm -f text="$(cat NAME.md)" > NAME.html
```

`$(...)` drops trailing newlines from the input, which doesn't change the rendering. Re-capture
a fixture when its Markdown changes, and keep inputs to features mdv renders like GitHub (no
fenced code with a language, headings, or raw HTML until their issues land).

## Comparison

Before comparing, the test removes what github.com adds on top of its Markdown rendering and mdv
deliberately leaves out:

| GitHub output                                    | Why mdv omits it                                   |
| ------------------------------------------------ | -------------------------------------------------- |
| `<markdown-accessiblity-table>` wrapper          | github.com custom element                          |
| `role="table"` on `<table>`                      | Redundant with the element's implicit role         |
| `rel="nofollow"` on links                        | SEO hint; mdv never navigates the viewer to links  |
| `class="notranslate"` on `pre`/`code`            | Browser translation hint for github.com            |
| `id=""` on task checkboxes                       | Empty attribute                                    |
| `user-content-` id/href prefix                   | DOM-clobbering guard for github.com's own page ids |
| `-<32 hex digits>` suffix on footnote ids        | Per-render nonce                                   |

Leading and trailing whitespace is trimmed on both sides; everything else must match exactly.
