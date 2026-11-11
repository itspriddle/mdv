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
  flavor is ignored, and the document renders with the default.
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

## Command line

`mdv FILE...` opens files in the app; with no FILE (or `-`), it reads Markdown from standard
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
- Errors are one line on standard error, such as `mdv: notes.md: No such file or directory`.

| Exit status | Meaning |
| --- | --- |
| 0 | Success |
| 64 | Usage error: bad flags, several pages to one output, `--output` naming an input, or no FILE while standard input is a terminal |
| 65 | An input isn't valid UTF-8 |
| 66 | An input file is missing or unreadable |
| 69 | The app couldn't be opened |
| 73 | The `--output` file couldn't be written |
| 74 | Writing to standard output failed |

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
