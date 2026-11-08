# Wiki links

Rendered with `.wikiLinks` on and the corpus resolver, whose pages are `Home.md`,
`Page-Name.md`, `guides/Setup.md`, and `../notes/Other Page.markdown`.

## Found

[[Home]], [[Page Name]], [[page-name]], [[PAGE NAME|a label]], [[Home.md]],
[[guides/Setup]], [[Other Page]], [[Home#Getting Started]], [[Home#Getting Started|start]],
and in this document [[#Not found]].

- In a list: [[Home]]
- [ ] In a task: [[Home|home]]

> In a quote: [[Home]]
> on a second line: [[Page Name]]

> [!TIP]
> In an alert: [[Home]]

| Page | Link |
| --- | --- |
| Home | [[Home\|home page]] |

Emphasis around a link: *[[Home]]* and **[[Home|bold]]**, ~~[[Home]]~~.
A footnote with a link.[^1]

Emoji in a label: [[Home|home :house:]].

[^1]: See [[Home]].

## Not found

[[Missing Page]], [[Missing|with a label]], [[../escape]], [[/absolute]], [[Missing#Heading]].

## Literal

\[[Escaped]], [\[Escaped]], [[Escaped\]], &#91;[Encoded]], `[[Code]]`, [[]], [[#]], [[ |x]],
[[a *b*]], [[a[b]]], [link [[Home]]](https://example.com), <https://example.com/[[Home]]>,
![[[Home]]](image.png), <span>[[Home]]</span> (raw HTML around text still links).

```
[[In a code block]]
```

    [[Indented code]]

<div title="[[In an attribute]]"></div>

## Escaping

[[\<script>|\<b>label\</b>]], [[Home|"quotes" & ampersands]], [[java:script]].
