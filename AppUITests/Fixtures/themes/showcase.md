---
title: Theme Showcase
tags: [themes, fixture]
author:
  name: mdv
---

# Theme Showcase

Every construct a theme styles, for checking the bundled themes by eye and for the visual
regression check (#39). The frontmatter above shows as a table when frontmatter display is
`table` (the app hides it by default).

## Inline text

Plain text with **bold**, *italic*, ***both***, ~~strikethrough~~, `inline code`, a
[relative link](README.md), an [external link](https://example.com), an autolink
<https://example.com/auto>, <kbd>⌘</kbd> + <kbd>F</kbd>, H<sub>2</sub>O, x<sup>2</sup>, an
emoji shortcode :sparkles:, and a footnote reference.[^note] A second footnote.[^long]

### Third-level heading

#### Fourth-level heading

##### Fifth-level heading

###### Sixth-level heading

## Lists

- Unordered item
- Item with a nested list
  - Nested item
    - Deeper item
- Item with a paragraph

  Second paragraph in the same item.

1. Ordered item
2. Another item
   1. Nested ordered item

- [x] Completed task
- [ ] Open task
  - [ ] Nested task

Term
: Definition lists aren't GFM, so this is a plain paragraph.

## Block quotes and alerts

> A block quote with **bold** text.
>
> > A nested block quote.

> [!NOTE]
> A note alert with `code` and a [link](README.md).

> [!TIP]
> A tip alert.

> [!IMPORTANT]
> An important alert.
>
> - with a list

> [!WARNING]
> A warning alert.

> [!CAUTION]
> A caution alert.

## Code

```swift
import Foundation

/// A greeting.
struct Greeter {
    let name: String
    func greet(times: Int = 1) -> String {
        String(repeating: "Hello, \(name)! ", count: times) // 42
    }
}
```

```javascript
const items = [1, 2, 3].map((n) => n * 2);
console.log(`doubled: ${items.join(", ")}`, /re+gex/g.test("ree"));
```

```python
@dataclass
class Point:
    x: float = 0.0
    def norm(self) -> float:
        return (self.x ** 2) ** 0.5  # absolute value
```

```diff
- removed line
+ added line
  unchanged line
```

```json
{ "name": "mdv", "private": true, "version": null, "count": 3 }
```

```
Plain code block without a language, with a long line that should scroll horizontally rather than wrap on screen.
```

## Tables

| Left | Center | Right | Code |
| :--- | :----: | ----: | ---- |
| One | Two | 3.00 | `a` |
| A longer cell | **bold** | 1,234.56 | `b()` |
| ~~struck~~ | [link](https://example.com) | 0 | |

## Images

A local image: ![Blue shape](assets/shape.svg)

A remote image, blocked in the viewer (placeholder): ![Remote badge](https://127.0.0.1:9/badge.png)

Light and dark only images (GitHub's convention):
![Light only](assets/shape.svg#gh-light-mode-only)![Dark only](assets/shape.svg#gh-dark-mode-only)

## Details and rules

<details>
<summary>Expandable details</summary>

Hidden content inside details.

</details>

---

Text after a thematic break. Theme showcase ends here.

[^note]: A short footnote.
[^long]: A longer footnote with `code` and a [link](https://example.com).
