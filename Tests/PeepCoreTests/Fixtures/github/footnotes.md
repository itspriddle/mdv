Footnotes are numbered by first reference[^later], not by definition[^first].

A note can be referenced again[^later] and again[^later]. Labels are case-insensitive[^First], and a missing definition stays literal[^missing].

| Tables | can reference |
| --- | --- |
| notes[^table] | too |

[^first]: The first definition, with *inline* markup and a [link](https://example.com).

[^later]:
    Block content works:

    - a list
    - of items

    ```
    and code
    ```

[^table]: Referenced from a table cell[^nested].

[^nested]: Referenced only from inside another note.

[^unused]: Never referenced, so never shown.
