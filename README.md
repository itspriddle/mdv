# mdv

A fast, native Markdown viewer for macOS, with a command-line companion.

```sh
mdv README.md
echo '# Markdown' | mdv
mdv --html README.md > README.html
```

> **Status:** early development. `mdv` is a working name. See [docs/VISION.md](docs/VISION.md) and
> [docs/ROADMAP.md](docs/ROADMAP.md).

## Themes

mdv ships GitHub, Document, and Serif themes, and any CSS file in
`~/Library/Application Support/mdv/Themes` is a theme too. See the
[theme authoring guide](docs/THEMES.md).

## Markdown flavors

Documents render as GitHub Flavored Markdown by default: tables, task lists, strikethrough,
autolinks, footnotes, emoji shortcodes, and GitHub alerts (`> [!NOTE]`). Settings > Markdown
switches the default to strict CommonMark, shows frontmatter as a table, and turns on wiki
links (`[[Page]]`). Open windows update right away.

## Per-document settings

A document can choose how it is shown with an `mdv:` mapping in its YAML frontmatter:

```yaml
---
mdv:
  flavor: commonmark   # or gfm (the default)
  theme: serif         # a bundled id, or custom:<file name>
  wikilinks: true      # [[Page]] links
---
```

- `flavor` is applied before the body is parsed, in the app and in `mdv --html`. An unknown
  flavor is ignored, and the document renders with the default. `mdv --flavor` beats it.
- `theme` beats the default theme from Settings, but a theme you pick for the window in View >
  Theme beats it (View > Theme > Document's Theme goes back). See the
  [theme guide](docs/THEMES.md#choosing-a-theme-per-document).
- `wikilinks` turns `[[Page]]` links on or off for that document, whatever Settings > Markdown
  says. `[[Page Name]]` opens `Page-Name.md` (or `Page Name.md`, any case), looked for in the
  document's folder, then anywhere in its repository (or folder).
- **What a document can't do:** these are the only keys. A document is untrusted input, so it
  can only choose among presentation options. It can't turn on the custom preprocessor, turn
  off HTML sanitizing, load remote images, or change any other safety setting. Other keys and
  values of the wrong type are ignored (and reported to the renderer, never shown as an error).
- Only YAML frontmatter (`---`) is read. TOML frontmatter (`+++`) is detected and hidden but not
  parsed, so `[mdv]` in TOML has no effect.

## Custom preprocessor

mdv can run a program of your choice on every document before rendering it, for formats or
conventions it doesn't know. It is off by default. Turn it on in Settings > Markdown > Custom
preprocessor: choose the program with Choose… and add any arguments, one per field.

- The program gets the document on standard input and writes Markdown to standard output; exit
  status 0 means success. The document's path is in `MDV_DOCUMENT_PATH`, and it runs in the
  document's folder with a minimal environment. Arguments are passed as given, with no shell.
- It runs as you, with your access to files, on every document you open. Only use a program you
  trust. A document can't turn it on or change it.
- It has 5 seconds and 10 MB of output. If it fails, the window shows the document without it
  and a bar with the reason; Show Details has what the program wrote to standard error.
- If macOS won't start it ("Operation not permitted"), the file may be quarantined, for example
  a script you downloaded. If you trust it, `xattr -d com.apple.quarantine /path/to/script`
  clears that.
- It runs again on every live reload, and open windows update when you change it in Settings.
- On the command line it runs only when you ask, never from the app's setting:
  `mdv --html --preprocessor ~/bin/expand --preprocessor-arg --strict notes.md`. The path is
  a file (relative to the current folder), never looked up on `PATH`; repeat
  `--preprocessor-arg` for each argument. Standard input runs it in `/` with no
  `MDV_DOCUMENT_PATH`. The limits are the app's. If it fails, mdv prints the reason and what it
  wrote to standard error, prints no HTML, and exits 70. Ctrl-C stops it (and anything it
  started) before mdv exits.

## Command line

`mdv FILE...` opens files in the app that contains the `mdv` command (launching it if needed),
like opening them from Finder; a file that is already open comes forward. Every path is checked
first, so a missing or unreadable file opens nothing. `mdv --theme serif FILE` opens the window
in that theme, as if picked from View > Theme. With no FILE (or `-`), it reads Markdown from standard
input. These flags render HTML instead:

```sh
mdv --html README.md > README.html        # a complete page: CSS inline, no external resources
mdv -o README.html README.md              # the same page written to a file
mdv --fragment intro.md usage.md > body.html   # body HTML only, for embedding
```

- `--html` prints one complete page per run. It is already standalone: styles are inline and a
  Content-Security-Policy blocks scripts and remote loads.
- `--fragment` prints only the rendered body (no `<html>`, `<head>`, or CSS). Several inputs
  print one after another; only fragments can share an output.
- `-o FILE` / `--output FILE` writes to FILE instead of standard output (`-o -` is standard
  output). It replaces FILE atomically, takes one input, and refuses to overwrite an input file.
- With no FILE and a terminal on standard input, mdv prints usage instead of waiting for input.
- `--theme NAME` picks the page's theme: `github`, `document`, `serif`, or `custom:<file name>`
  from the Themes folder (`~/Library/Application Support/mdv/Themes`, or `MDV_THEMES_FOLDER`).
  `--flavor NAME` picks the syntax: `gfm` or `commonmark` (HTML output only: windows follow
  Settings > Markdown and `mdv.flavor`). **A flag beats the document's
  `mdv:` frontmatter, which beats the default** (GitHub, GFM), as a View > Theme pick does in
  the app. An unknown name is a usage error; a custom theme that is missing (66) or fails its
  checks (65) is an error with the reason. Without `--theme`, the document's `mdv.theme`
  (bundled or custom) picks the theme, falling back to GitHub silently.
- `--list-themes` and `--list-flavors` print one `id<TAB>name` line each (custom theme files
  that don't load are reported on standard error).
- Rendering flags: `--frontmatter table` shows frontmatter before the body (hidden by default);
  `--wiki-links` / `--no-wiki-links` turn `[[wiki links]]` on or off, beating the document's
  `mdv.wikilinks`; `--source-lines` adds `data-source-line` attributes; `--no-highlight` and
  `--no-heading-anchors` turn those off; `--block-remote-images` replaces remote images with a
  placeholder (they're kept by default, as on GitHub). Raw HTML is always sanitized; there is no
  flag to turn that off. The CLI ignores the app's Settings: output depends only on the flags
  and the file.
- For a FILE, wiki links resolve from its folder and then its repository (or folder), and
  root-relative links (`/docs/x.png`) resolve against that root as absolute paths, as in the
  app. Links to other pages stay `.md`. Standard input has no folder, so page links show as
  missing.
- Frontmatter `mdv:` keys mdv ignored are reported on standard error as warnings
  (`mdv: notes.md: warning: mdv.sanitize isn't a setting a document can change ...`);
  `--verbose` also reports the flavor and wiki link setting used and where each came from.
- Errors are one line on standard error, such as `mdv: notes.md: No such file or directory`.

| Exit status | Meaning |
| --- | --- |
| 0 | Success |
| 64 | Usage error: bad flags, several pages to one output, `--output` naming an input, or no FILE while standard input is a terminal |
| 65 | An input isn't valid UTF-8, or the `--theme` file isn't a valid theme |
| 66 | An input file is missing or unreadable, or the `--theme` file is missing |
| 69 | The app couldn't be opened |
| 70 | The `--preprocessor` program couldn't run or failed |
| 73 | The `--output` file couldn't be written |
| 74 | Writing to standard output failed |

## Command line tool

The `mdv` command ships inside the app. To put it on your `PATH`, choose mdv > Install Command
Line Tool…, pick a folder, and click Install. mdv adds a link named `mdv` to the command in the
copy of mdv you are running (the alert names it, which matters if you have several copies).

- `~/.local/bin` needs no password, but your shell may not look there. If `mdv` isn't found in a
  new terminal window, add `export PATH="$HOME/.local/bin:$PATH"` to your shell's startup file
  (`~/.zshrc` for zsh). mdv suggests this folder when your login shell already has it on `PATH`.
- `/usr/local/bin` is on every `PATH` but asks for an administrator's password.
- mdv never replaces or removes anything that isn't its own link. If a file, a folder, or a link
  to another program is already named `mdv` there, it tells you what it found and stops.
- If you move or rename mdv.app, the link breaks; the menu item becomes Repair Command Line
  Tool…, which points the link at the copy you are running.
- When it is installed, the item is Uninstall Command Line Tool…, which removes the link (and
  only the link). You can also delete it yourself: `rm ~/.local/bin/mdv` or
  `sudo rm /usr/local/bin/mdv`.

## Requirements

- macOS 15 or later
- Xcode 26+ (Swift 6) to build from source

## Building

```sh
make bootstrap     # brew install xcodegen swiftlint
make generate      # create mdv.xcodeproj from project.yml (the project file is not committed)
open mdv.xcodeproj
```

Signed local builds: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your
`DEVELOPMENT_TEAM`. Without it, build unsigned with `make build SIGN=0`.

| Command            | What it does                               |
| ------------------ | ------------------------------------------ |
| `make build`       | Build the app and embedded CLI             |
| `make test`        | Run core (`swift test`) and app test suites |
| `make lint`        | SwiftLint + swift-format lint (strict)     |
| `make format`      | Auto-format sources                        |

## Project layout

| Path               | Contents                                                       |
| ------------------ | -------------------------------------------------------------- |
| `Sources/MdvCore`  | Rendering engine (Swift package, UI-free, fully unit-tested)   |
| `App`              | SwiftUI macOS app                                              |
| `CLI`              | `mdv` command-line tool, embedded in `mdv.app/Contents/Helpers` |
| `project.yml`      | XcodeGen spec for the app, CLI, and app tests                  |

## License

[MIT](LICENSE)
