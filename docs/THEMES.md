# Writing mdv themes

An mdv theme is one plain CSS file. Drop it in the Themes folder and it shows up in the theme
picker; save it again and every window showing it updates. There is no build step, no
manifest, and no scripting.

This guide covers everything a theme can rely on: where the file goes, the optional header,
the HTML you style, light and dark mode, print, the content width control, and what mdv
rejects (and why). A [complete example theme](#a-complete-example) is at the end.

## Quick start

1. Choose **View > Theme > Open Themes Folder** (or **Settings > General > Open Themes
   Folder**). mdv creates `~/Library/Application Support/mdv/Themes` if needed and opens it in
   Finder.
2. Save a file named `My Theme.css` there:

   ```css
   /* mdv-theme
      name: My Theme
      extends: github
   */
   .markdown-body { font-family: ui-serif, Georgia, serif; }
   .markdown-body h1, .markdown-body h2 { color: #8a3b12; }
   ```

3. Open a Markdown file and choose **View > Theme > My Theme** (or use the theme menu in the
   window's toolbar). To use it for every new window, pick it under **Settings > General >
   Default theme**.
4. Edit the file in any editor. Each save updates every window showing the theme, in place,
   keeping your reading position.

`extends: github` starts from the bundled GitHub theme, so a theme can be a few overrides. To
write everything yourself, leave `extends` out and start from the
[complete example](#a-complete-example).

## Where theme files go

- **Folder:** `~/Library/Application Support/mdv/Themes`. It may be a symbolic link to a folder
  elsewhere (a dotfiles repository, say).
- **Files:** every visible file ending in `.css` (any case: `.CSS` works) is one theme. Files
  whose names start with `.` and files with other extensions are ignored.
- **Each file must be** a regular file (not a symbolic link, folder, or pipe), at most 512 KB,
  UTF-8 text (a byte order mark is fine) with no NUL bytes.
- **At most 100 themes** load, in Finder's name order; the rest are reported as not loaded.
- **Identity:** a custom theme is known by its file name (internally `custom:<file name>`).
  Windows and Settings remember a theme by that name, so renaming the file is like deleting
  the theme and adding a new one: windows using the old name show the default theme from
  **Settings > General** (GitHub if that is missing too) until a file with that name comes
  back. Custom themes can't replace bundled ones; they are listed in their own section of the
  picker.

## The header

A theme may start with a header comment declaring its metadata. Every key is optional, and so
is the header:

```css
/* mdv-theme
   name: Solarized Light
   background: #fdf6e3
   background-dark: #002b36
   extends: github
*/
```

The rules:

- It must be the **first thing in the file** (whitespace before it is fine) and a `/* … */`
  comment whose first line is `mdv-theme`. A first comment without that marker is an ordinary
  comment, and the theme gets the defaults below.
- Every other non-blank line is `key: value`. Keys are case-insensitive. A leading `*` on a
  line (comment decoration) is ignored.
- Unknown keys, repeated keys, and lines that aren't `key: value` are errors, so a typo like
  `backgound:` is reported instead of silently ignored.

| Key               | Value                                     | Default                                                       |
| ----------------- | ----------------------------------------- | ------------------------------------------------------------- |
| `name`            | The name shown in menus, at most 64 characters (longer names are cut) | The file name without `.css`                                  |
| `background`      | Page background in light mode: `#rgb` or `#rrggbb` | The extended theme's, else GitHub's `#ffffff`                 |
| `background-dark` | Page background in dark mode: `#rgb` or `#rrggbb`  | `background` if given, else the extended theme's, else GitHub's `#0d1117` |
| `extends`         | A bundled theme id: `github`, `document`, or `serif` (lowercase) | None: the theme starts from browser defaults                  |

### Backgrounds

The backgrounds are in the header, not only in CSS, because mdv paints the window with them
before the page exists. That's what keeps a dark theme from flashing white when a window
opens or the theme changes. mdv also generates the page's `body` background from them, so
you don't need to write one.

Only hex colors work (no names, `rgb()`, or alpha): the window background has to be a solid
color mdv can read without a CSS engine. If the page should look different from a flat color
(a gradient, a "sheet of paper" on a desk), give `body` or `.markdown-body` a background in
your CSS and set the header colors to the closest flat color, which is what shows while the
window opens and past the ends of the page when you scroll beyond them.

Giving only `background` uses the same color in dark mode. That's right for a theme that
looks the same in both appearances, but read [Light and dark](#light-and-dark) first.

### `extends`

`extends: github` (or `document`, `serif`) puts that bundled theme's CSS (its stylesheet,
syntax colors, and print rules) first, then your file. Your rules come later in the same
layer, so at equal specificity yours win: write the bundled theme's selector (usually
`.markdown-body something`) and change what you want. The header's backgrounds replace the
bundled theme's.

Only bundled themes can be extended (a custom theme can't extend another custom theme). The
bundled themes' CSS lives in mdv's source under
[`Sources/MdvCore/Themes`](../Sources/MdvCore/Themes) if you need to see what you're
overriding; GitHub's is [github-markdown-css](https://github.com/sindresorhus/github-markdown-css)
plus a few additions.

Without `extends`, a theme starts from the browser's defaults plus mdv's base rules, and has
to style everything itself, including the syntax highlighting colors.

## How the page is built

Every window shows an HTML page with three stylesheets, in three
[CSS cascade layers](https://developer.mozilla.org/en-US/docs/Web/CSS/@layer):

```html
<style id="mdv-base">  @layer mdv-base, mdv-theme, mdv-user;  @layer mdv-base { … } </style>
<style id="mdv-theme"> @layer mdv-theme { …your theme… } </style>
<style id="mdv-user">  @layer mdv-user { …the reader's controls… } </style>
…
<body>
<article class="markdown-body">
  …the rendered document…
</article>
</body>
```

- **`mdv-base`**: rules mdv's features depend on. Most are defaults that your theme overrides
  without trying: a rule in a later layer beats an earlier layer's whatever the selectors'
  specificity, so you never need `!important` or long selectors to beat mdv.
- **`mdv-theme`**: your file (after the extended theme, if any).
- **`mdv-user`**: the reader's View > Content Width choice. It beats your theme the same way.

### What a theme can't change

Some base rules are marked `!important`. For important declarations the cascade runs the other
way (an earlier layer's important rule beats a later one's, important or not), so **no theme
can undo them**, even with `!important`. They're what keeps viewer features working and paper
readable whatever the theme says:

- **Find in page:** the highlight colors of matches (`::highlight(mdv-find)`) and the current
  match.
- **Blocked remote images:** the placeholder (`.remote-image`) is always displayed and visible.
  Its look (border, colors, size) is yours to change.
- **Light- and dark-only images:** images whose URL ends in `#gh-light-mode-only` or
  `#gh-dark-mode-only` (GitHub's convention), and their placeholders, show only in the
  matching appearance. Paper counts as light.
- **Screen reader text:** `.sr-only` stays visually hidden.
- **Paper:** see [Print](#print).

The document's own HTML can't style anything either: `style` attributes, `<style>` elements,
and `class` attributes in a document's raw HTML are removed, so a theme only has to handle the
markup below.

## The markup you style

Everything is inside `<article class="markdown-body">`, a child of `body`. Scope your rules
with `.markdown-body` (the bundled themes do), except the `hljs-*` token classes, which only
appear in code blocks. Typical output:

| Content | Markup |
| --- | --- |
| Paragraphs, emphasis, strikethrough | `p`, `strong`, `em`, `del` |
| Links | `a` |
| Headings | `h1`–`h6` with an `id` (the slug used in `#fragment` links) and an empty first child `<a class="anchor" aria-hidden="true" href="#slug"></a>` |
| Lists | `ul`, `ol`, `li`. A loose list item wraps its text in `p`. |
| Task lists | `<ul class="contains-task-list">` → `<li class="task-list-item">` → `<input type="checkbox" disabled class="task-list-item-checkbox">` (`checked` when done) then the text |
| Block quotes | `blockquote`, nested for nested quotes |
| Alerts | GitHub alerts (`> [!NOTE]`, GFM flavor): `<div class="markdown-alert markdown-alert-note">` (also `markdown-alert-tip`, `markdown-alert-important`, `markdown-alert-warning`, `markdown-alert-caution`) holding `<p class="markdown-alert-title">` (an `<svg class="octicon">` icon, then the title) and the body blocks. The base layer gives them a left rule in the text color and lays out the title; colors are yours. |
| Code blocks | `<pre><code class="language-swift">` (no class without a language) with highlight.js token spans inside |
| Inline code, keys | `code`, `kbd` (from raw HTML) |
| Tables | `table` → `thead`/`tbody` → `tr` → `th`/`td`; column alignment is an `align` attribute (`th[align="right"]`) |
| Images | `img`. Local images load; remote ones are replaced by a placeholder (below) until the reader allows them. |
| Footnotes | References: `<sup><a href="#fn-note" id="fnref-note" data-footnote-ref>1</a></sup>`. Notes: `<section class="footnotes" data-footnotes>` holding a visually hidden `h2.sr-only` and an `ol` of `li id="fn-note"`, each ending with a back link `<a class="data-footnote-backref" data-footnote-backref>↩</a>` |
| Thematic breaks | `hr` |
| Raw HTML | Allowed elements such as `details`/`summary`, `sub`, `sup`, `mark`, `kbd`, `picture`, `figure` keep their tags |

Block elements also carry a `data-source-line` attribute, which the app uses to keep your
place; don't rely on it for styling.

### Heading anchors

The anchor link is empty: mdv writes no icon. If you want one, give it content and show it on
hover, as the bundled themes do:

```css
.markdown-body h1, .markdown-body h2, .markdown-body h3 { position: relative; }
.markdown-body .anchor {
  position: absolute; left: -1em; width: 1em; text-align: center; text-decoration: none; opacity: 0;
}
.markdown-body .anchor::before { content: "#"; }
.markdown-body :hover > .anchor, .markdown-body .anchor:focus { opacity: 1; }
```

Leave it unstyled and it takes no space. It's always hidden on paper.

### Syntax highlighting

Code blocks that name a language are highlighted when the document is rendered by
[highlight.js](https://highlightjs.org/), which wraps tokens in `<span class="hljs-…">`
elements (for example `hljs-keyword`, `hljs-string`, `hljs-number`, `hljs-comment`,
`hljs-title function_`, `hljs-built_in`, `hljs-attr`, `hljs-addition`, `hljs-deletion`).
highlight.js's [CSS class reference](https://highlightjs.readthedocs.io/en/latest/css-classes-reference.html)
lists them all. Any highlight.js theme's CSS works as a starting point if you drop its
`.hljs` (block background) rule, since mdv doesn't put an `hljs` class on the block: style
`.markdown-body pre` instead.

A theme without `extends` gets no token colors until it writes some; code then shows in the
code block's text color.

### Frontmatter

YAML or TOML frontmatter at the top of a file is hidden unless the reader turns on
Settings > Markdown > Frontmatter > Shown as a Table. Then it appears above the document: YAML
as a table of top-level keys and values (lists are comma-separated, nested mappings are nested
tables without the class), TOML as a code block:

```html
<table class="frontmatter">
<tbody>
<tr>
<th>title</th>
<td>Release notes</td>
</tr>
</tbody>
</table>

<pre class="frontmatter"><code class="language-toml">title = "Release notes"</code></pre>
```

Both get your ordinary `table` and `pre` styles, so a theme that styles those already covers
them. The classes let you style them apart from the document's own tables and code, for
example:

```css
.markdown-body table.frontmatter { font-size: 0.875em; }
.markdown-body table.frontmatter th,
.markdown-body table.frontmatter td { text-align: left; vertical-align: top; }
```

### Blocked remote images

The viewer doesn't load images from the web until the reader allows them for the window.
Until then each remote image is a placeholder:

```html
<span class="remote-image" role="img" aria-label="Blocked remote image: Build (img.shields.io)"
      title="https://img.shields.io/badge.svg">
  <span class="remote-image-alt">Build</span><span class="remote-image-host">img.shields.io</span>
</span>
```

mdv gives it a dashed box, muted colors, and dark-mode colors; restyle any of that with
`.markdown-body .remote-image`, `.remote-image-alt`, and `.remote-image-host`. You can't hide it
(`display: none` and `visibility: hidden` are overridden), so readers always see that an image
was blocked.

## Light and dark

mdv follows the system appearance live (or the one picked in Settings > Appearance). Write the light colors first and the dark ones under
`@media screen and (prefers-color-scheme: dark)`:

```css
.markdown-body { --text: #24292f; --link: #0969da; color: var(--text); }
@media screen and (prefers-color-scheme: dark) {
  .markdown-body { --text: #e6edf3; --link: #4493f8; }
}
```

Always include `screen and`. Paper is always printed light, and a bare
`(prefers-color-scheme: dark)` block could apply to it.

The page declares `color-scheme: light dark`, so in dark mode the browser's own defaults
(text color, form controls such as task-list checkboxes, scroll bars) turn dark. A theme with
dark colors wants that. A **light-only** theme should opt out, or its default text turns light
on its light background in dark mode:

```css
:root { color-scheme: light; }
```

and give only `background` in the header (it's used in both appearances).

## Content width

**View > Content Width** lets the reader pick Narrow, Theme Default, Wide, or Full Width for
a window (**Settings** picks it for new windows). "Theme Default" is whatever your theme sets.

- Limit width on `.markdown-body` and you need to do nothing: for the other choices mdv sets
  `.markdown-body`'s `max-width` itself, above your theme.
- If you limit width on some other element (a wrapper, `body`), read the variable mdv sets,
  `--mdv-content-width`: `max-width: var(--mdv-content-width, 44em);` (the second value is your
  default). It's the
  only variable mdv sets, and only while the reader has picked something other than Theme
  Default; its values are `32em`, `72em`, or `none`.
- Writing `.markdown-body { max-width: var(--mdv-content-width, 44em) }` anyway makes the
  intent clear; the bundled themes do.
- Don't mark `max-width` `!important`; that would beat the reader's choice.
- Widths are in `em`, so they follow your column's font size: Narrow is about 60–70
  characters per line in any theme. Keep your own default above about 40em, or Narrow ends up
  wider than Theme Default.

Text size is not a theme control for the reader: View > Zoom In/Out (Cmd +/-) scales the
whole page, your theme included.

## Print

Printing and Save as PDF use the window's theme. Write paper-only rules in `@media print`:

```css
@media print {
  .markdown-body { font-size: 15px; }
  .markdown-body a { color: inherit; }
}
```

What the base layer guarantees on paper, whatever the theme says:

- Paper is **light**: the color scheme is light and dark-mode rules don't apply (if they're
  under `@media screen and …`).
- The **page background never prints** (`print-color-adjust: economy` on the page). Your
  header backgrounds and any `body` background stay on screen.
- **Full width:** `.markdown-body` has no `max-width` and no padding on paper (the page
  margins come from Page Setup). Content Width doesn't apply to paper.
- **Nothing is clipped:** code wraps instead of scrolling, tables are full width and wrap,
  images fit the page.
- **No anchor icons**, and page breaks avoid splitting table rows and images and never fall
  right after a heading.

Defaults you may change: external links are followed by their URL in parentheses (style or
remove it with `.markdown-body a[href^="http"]::after`), and paragraphs keep at least three
lines together at page breaks.

Element backgrounds (code blocks, table stripes, diff lines) don't print unless the theme
asks for them, as browsers do to save ink. Opt an element in with
`print-color-adjust: exact`; the bundled themes do for code, `kbd`, `mark`, and tables:

```css
@media print {
  .markdown-body pre, .markdown-body code, .markdown-body table { print-color-adjust: exact; }
}
```

Sizes: WebKit lays a page out at 1.25 CSS pixels per point, so 16px text prints at about
12.8pt. Around 15–16px makes comfortable paper text.

## Fonts and images

- **Fonts:** use fonts installed on the Mac, by name: `font-family: "Avenir Next", sans-serif`.
  The system's own families are `-apple-system` (San Francisco), `ui-serif` (New York),
  `ui-monospace` (SF Mono), and `ui-rounded`. Web fonts can't be loaded: the page allows no
  font downloads, and `url()` accepts only images (below).
- **Images:** `url()` works with `data:image/…` URLs only, e.g. a small SVG or PNG embedded in
  the file for a list marker or a background texture:
  `background-image: url("data:image/svg+xml,…")`. SVG used this way can't run scripts or load
  anything. Mind the 512 KB file limit.

## What's rejected, and why

A theme runs inside a viewer that loads nothing from the network and runs no document
scripts. The page's Content Security Policy already blocks any request a stylesheet could
make; mdv also checks each theme file before using it, so a theme that would try never
renders differently than you wrote it without saying why. A file that breaks a rule isn't
loaded at all (nothing is quietly stripped):

- **`@import`**: a theme is one self-contained file.
- **`url()` that isn't `data:image/…`**: no `http:`, `https:`, `file:`, or relative URLs, no
  fonts. The same goes for URL strings in `image-set()`, `-webkit-image-set()`, `image()`,
  `src()`, and `cross-fade()`.
- **`expression()`**: an old Internet Explorer feature; never valid.
- **Unbalanced brackets, comments, or strings**: every `{`, `(`, and `[` must close, and
  every comment and string must end. A stray `}` would let rules escape the theme's layer.

The check understands CSS comments, strings, and escapes, and ignores case, so
`@\69mport` and `URL(` are caught too; text inside comments and strings doesn't count.

## When a theme doesn't load

A file that can't be used isn't an alert: it's listed, disabled, at the end of
**View > Theme** as its name and the reason, and under
**Settings > General**. Fix the file and save; it loads at once. While it's broken, windows
that were showing it fall back to the default theme set in **Settings > General** (GitHub, the
built-in default, if that one is missing or broken too), and switch back when it loads again.

| Problem | What mdv says |
| --- | --- |
| `@import "base.css";` | @import isn’t allowed (line 1) |
| `background: url(paper.png);` | Only data:image URLs are allowed in url() (line 1) |
| `width: expression(1);` | expression() isn’t allowed (line 1) |
| A stray `}` | Unmatched “}” (line 1) |
| A `{` never closed | “{” is never closed (line 1) |
| A `/*` never closed | Comment is never closed (line 1) |
| `content: "x;` | String is never closed (line 1) |
| `background: white` in the header | background must be a hex color like #ffffff, not “white” (line 2) |
| `colour: red` in the header | Unknown header key “colour” (line 2) |
| `name:` given twice | “name” appears twice in the header (line 3) |
| A header line without a colon | Expected “key: value” in the header (line 2) |
| `extends: GitHub` | “extends: GitHub” names no bundled theme |
| A symbolic link | Symbolic links aren’t loaded; copy the file into the Themes folder |
| Over 512 KB | Too large (600 KB; the limit is 512 KB) |
| Not UTF-8 | Not UTF-8 text |
| Binary data | Contains NUL bytes; not a text file |
| More than 100 theme files | More than 100 themes; the rest aren’t loaded |

Line numbers count from the top of the file.

## Hot reload

mdv watches the Themes folder while it runs, including when it doesn't exist yet. Within a
fraction of a second of a change:

- a **new file** appears in the picker;
- an **edited file** updates every window showing it, in place: no reload, no flash, same
  scroll position (atomic saves from editors are fine);
- a **deleted or broken file** disappears from the picker (or shows as not loaded), and
  windows showing it fall back to the Settings default theme (GitHub if that one is missing
  too). They keep their choice, so the theme comes back when the file does.

A save that's briefly invalid while you're typing (an unclosed `{`) shows the Settings default
theme until the next valid save.

## Choosing a theme per document

A Markdown file can name the theme it should open in, in its YAML frontmatter under `mdv:`:

```yaml
---
title: Release notes
mdv:
  theme: custom:Release Notes.css
---
```

- **Ids:** a bundled theme by id (`github`, `document`, `serif`; case doesn't matter) or a
  custom one as `custom:<file name>` (exactly as the file is named, `.css` included).
- **Precedence:** a theme you pick for that window in **View > Theme** wins over the
  document's, and the document's wins over the **Settings > General** default. **View > Theme >
  Document's Theme** drops your pick and goes back to the document's theme.
- **Missing themes** fall back like a deleted custom theme: an id that isn't loaded (yet) shows
  the Settings default, and the document's theme appears as soon as its file loads.
- **Editing the frontmatter** while the file is open swaps the theme in place, like a theme
  edit. Window restoration only remembers your own pick, so a changed `mdv.theme` applies the
  next time the document opens too.
- `mdv --html` uses a bundled theme the document names; anything else gets GitHub.

The same block can set the document's Markdown flavor; see the
[README](../README.md#per-document-settings) for every key and what a document can't change.

## A complete example

[`example-theme.css`](example-theme.css) is a whole theme written without `extends`: light and
dark colors, a reading column that follows Content Width, heading anchors, task lists, code
with syntax colors, tables, footnotes, the remote-image placeholder, and print rules. Copy it
into the Themes folder, pick **View > Theme > Notebook**, and change it from there. (mdv's
tests load this file, and check that the copy below matches it.)

```css
/* mdv-theme
   name: Notebook
   background: #fbfaf7
   background-dark: #1c1b19
*/

/* Notebook: a complete theme written from scratch (no `extends`). Copy it to
   ~/Library/Application Support/mdv/Themes/ and pick View > Theme > Notebook. */

/* Colors, light first. Dark colors are screen only, so paper always prints light. */
.markdown-body {
  --nb-text: #2b2a27; --nb-muted: #6d6a63; --nb-accent: #8a3b12; --nb-rule: #e3dfd6;
  --nb-code-bg: #f1eee7;
  --nb-keyword: #8a3b12; --nb-string: #2f6b3a; --nb-number: #1f5a96; --nb-comment: #8b867c;
  --nb-title: #6b3fa0; --nb-added: #e3f1e3; --nb-removed: #f8e2e0;
}
@media screen and (prefers-color-scheme: dark) {
  .markdown-body {
    --nb-text: #e6e2da; --nb-muted: #a29d93; --nb-accent: #f0a46b; --nb-rule: #3a3833;
    --nb-code-bg: #292824;
    --nb-keyword: #f0a46b; --nb-string: #9ccf8f; --nb-number: #8fbbe8; --nb-comment: #8b867c;
    --nb-title: #c9a6f0; --nb-added: #23361f; --nb-removed: #43221f;
  }
}

/* The page and the reading column. */
body { margin: 0; }
.markdown-body {
  box-sizing: border-box; max-width: var(--mdv-content-width, 44em); margin: 0 auto;
  padding: 48px 32px 64px; color: var(--nb-text);
  font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 17px; line-height: 1.6;
  overflow-wrap: break-word;
}
.markdown-body > :first-child { margin-top: 0; }
.markdown-body a { color: var(--nb-accent); }
.markdown-body img { max-width: 100%; }
.markdown-body hr { border: 0; border-top: 1px solid var(--nb-rule); margin: 2em 0; }
.markdown-body blockquote {
  margin: 0 0 1em; padding: 0 1em; border-left: 3px solid var(--nb-rule); color: var(--nb-muted);
}

/* Headings and their anchor links (empty <a class="anchor">: give it something to show). */
.markdown-body h1, .markdown-body h2, .markdown-body h3,
.markdown-body h4, .markdown-body h5, .markdown-body h6 {
  position: relative; margin: 1.6em 0 0.5em; line-height: 1.25;
  font-family: ui-serif, "New York", Georgia, serif;
}
.markdown-body h1 { font-size: 2em; }
.markdown-body h2 { font-size: 1.5em; padding-bottom: 0.2em; border-bottom: 1px solid var(--nb-rule); }
.markdown-body h3 { font-size: 1.25em; }
.markdown-body h4, .markdown-body h5, .markdown-body h6 { font-size: 1em; }
.markdown-body .anchor {
  position: absolute; left: -1em; width: 1em; text-align: center; text-decoration: none;
  color: var(--nb-muted); opacity: 0;
}
.markdown-body .anchor::before { content: "#"; }
.markdown-body :hover > .anchor, .markdown-body .anchor:focus { opacity: 1; }

/* Lists and task lists. */
.markdown-body .contains-task-list { padding-left: 1.4em; }
.markdown-body .task-list-item { list-style-type: none; }
.markdown-body .task-list-item-checkbox { margin: 0 0.4em 0 -1.3em; vertical-align: middle; }

/* Code. highlight.js tokens are <span class="hljs-…"> inside pre > code. */
.markdown-body code, .markdown-body kbd, .markdown-body pre {
  font-family: ui-monospace, Menlo, monospace; font-size: 0.875em;
}
.markdown-body code { padding: 0.1em 0.3em; border-radius: 4px; background: var(--nb-code-bg); }
.markdown-body pre {
  padding: 12px 16px; overflow: auto; line-height: 1.45; border-radius: 6px; background: var(--nb-code-bg);
}
.markdown-body pre code { padding: 0; font-size: 1em; background: none; }
.markdown-body kbd { padding: 0.1em 0.4em; border: 1px solid var(--nb-rule); border-radius: 4px; }
.hljs-keyword, .hljs-type, .hljs-built_in, .hljs-meta { color: var(--nb-keyword); }
.hljs-string, .hljs-regexp { color: var(--nb-string); }
.hljs-number, .hljs-literal, .hljs-attr, .hljs-variable { color: var(--nb-number); }
.hljs-title { color: var(--nb-title); }
.hljs-comment, .hljs-quote { color: var(--nb-comment); font-style: italic; }
.hljs-addition { background-color: var(--nb-added); }
.hljs-deletion { background-color: var(--nb-removed); }

/* Tables. */
.markdown-body table {
  display: block; width: max-content; max-width: 100%; overflow: auto; border-collapse: collapse;
}
.markdown-body th, .markdown-body td { padding: 4px 10px; border: 1px solid var(--nb-rule); }

/* Footnotes. */
.markdown-body .footnotes {
  margin-top: 2em; border-top: 1px solid var(--nb-rule); font-size: 0.875em; color: var(--nb-muted);
}

/* Blocked remote images: restyle the placeholder (it can't be hidden). */
.markdown-body .remote-image { border-color: var(--nb-rule); background: var(--nb-code-bg); color: var(--nb-muted); }

/* Paper: a slightly smaller body, links in the text color, code and diff fills kept. */
@media print {
  .markdown-body { font-size: 15px; }
  .markdown-body a { color: inherit; }
  .markdown-body pre, .markdown-body code { print-color-adjust: exact; }
}
```

## An `extends` example: GitHub Soft Dark

[`github-soft-dark.css`](github-soft-dark.css) is github.com's **Soft dark** appearance
(Primer's `dark_dimmed` palette), written as a few lines on top of `extends: github`. The
GitHub theme takes all of its colors, syntax colors included, from Primer's CSS variables
(`--fgColor-default`, `--bgColor-muted`, `--color-prettylights-syntax-keyword`, …), so the
theme redefines those for dark mode and sets `background-dark` to match `--bgColor-default`.
Light mode stays the bundled GitHub theme. The same approach works for Primer's other
palettes, such as high contrast or the colorblind ones.

## Checklist

- [ ] The header (if any) is the very first thing in the file and starts with `mdv-theme`.
- [ ] `background` and `background-dark` match what the page looks like in each appearance.
- [ ] Dark colors are under `@media screen and (prefers-color-scheme: dark)`, or the theme
      sets `:root { color-scheme: light; }`.
- [ ] Widths are on `.markdown-body`, or use `var(--mdv-content-width, …)`.
- [ ] Code blocks have token colors (or the theme extends a bundled one).
- [ ] Check a document with every construct in light, dark, and File > Print's preview.
