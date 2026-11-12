Each type, any case:

> [!NOTE]
> A note.

> [!tip]
> A tip.

> [!Important]
> Important.

> [!WARNING]
> A warning.

> [!cAuTiOn]
> Caution.

Spacing around the marker:

>[!NOTE]
>No space after the quote marker.

>   [!NOTE]
> Indented marker.

> [!NOTE]   
> Trailing spaces.

> [!NOTE]	
> Trailing tab.

Line breaks after the marker:

> [!NOTE]  
> Hard break.

> [!NOTE]\
> Backslash break.

> [!NOTE]<br>
> Raw br.

Escaped and entity markers:

> \[!NOTE]
> Escaped bracket.

> [\!NOTE]
> Escaped bang.

> &#91;!NOTE]
> Entity bracket.

> [!N&#79;TE]
> Entity letter.

Body shapes:

> [!NOTE]
Lazy continuation.

> [!TIP]
>
> The marker in its own paragraph.

> [!IMPORTANT]
> - a list
> - right after

> [!WARNING]
> ***

> [!CAUTION]
> ```
> ```

> [!NOTE]
> | a |
> |---|
> | b |

> [!NOTE]
> <div>raw block</div>

> [!NOTE]
> <span></span>

> [!NOTE]
> &nbsp;

> [!WARNING]
> *em* and :tada: and `code`.

> [!NOTE]
> First paragraph.
>
> Second paragraph.

No nesting:

> [!NOTE]
> Outer.
> > [!TIP]
> > Inner stays a quote.

> > [!NOTE]
> > Nested quote.

- > [!NOTE]
  > In a list item.

Footnote.[^1]

[^1]: > [!NOTE]
    > In a footnote.

Not alerts:

> [!NOTE]

> [!NOTE]
>

> [!NOTE]
> <!-- only a comment -->

> [!NOTE]<br>

> [!NOTE] Text on the marker line.

> [!NOTE] `code`

> [!NOTE] <b>html</b>

> [!FOO]

> [! NOTE]

> [!NOTE ]

> **[!NOTE]**

> [!NOTE]&nbsp;

> [!NO\TE]

> intro
>
> [!NOTE]

> ```
> [!NOTE]
> ```
