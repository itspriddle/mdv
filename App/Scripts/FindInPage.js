// mdv find in page: finds text in the rendered document, counts and highlights every match, and
// scrolls the current one into view.
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `mdvFind`. Swift calls these functions with
// callAsyncJavaScript and passes the query as an argument, never as script source.
//
// Highlights use the CSS Custom Highlight API: ranges registered in `CSS.highlights` are painted
// by the `::highlight(mdv-find)` and `::highlight(mdv-find-current)` rules in the page's
// stylesheet (DefaultTheme). Nothing is inserted into the DOM and no inline style is set, so
// `data-source-line` positions, link hover, and live reload swaps are unaffected, and the page's
// CSP (`style-src 'unsafe-inline'`, no scripts) is irrelevant to it. The highlight registry
// belongs to the document, so ranges registered from this world are painted on the page.
"use strict";

(() => {
  const ALL = "mdv-find";
  const CURRENT = "mdv-find-current";
  // Counting stops here (shown as "1000+"); bounds the work a huge document can cause.
  const MAXIMUM_MATCHES = 1000;
  const MAXIMUM_QUERY_LENGTH = 1000;
  // Text in different blocks is joined with this, so a match never spans two paragraphs. The
  // renderer never emits NUL (cmark replaces it), and it is removed from queries.
  const SEPARATOR = "\u0000";
  const BLOCKS = [
    "address", "article", "aside", "blockquote", "dd", "details", "div", "dl", "dt", "figcaption",
    "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "nav",
    "ol", "p", "pre", "section", "summary", "table", "td", "th", "tr", "ul",
  ].join(", ");
  const HIDDEN = "script, style, template, noscript";

  let matches = [];
  let current = -1;

  function scope() {
    return document.querySelector("article.markdown-body") ?? document.body;
  }

  // Whether text directly inside `element` is rendered. Cached per element for one search.
  function isShown(element, cache) {
    let shown = cache.get(element);
    if (shown === undefined) {
      shown = element.closest(HIDDEN) === null
        && (typeof element.checkVisibility !== "function"
          || element.checkVisibility({ visibilityProperty: true }));
      cache.set(element, shown);
    }
    return shown;
  }

  // The rendered text of the document as one string, with each text node's offset in it.
  function collectText(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const cache = new Map();
    const nodes = [];
    let text = "";
    let previousBlock;
    for (let node = walker.nextNode(); node !== null; node = walker.nextNode()) {
      const parent = node.parentElement;
      if (parent === null || node.data.length === 0 || !isShown(parent, cache)) {
        continue;
      }
      const block = parent.closest(BLOCKS);
      if (block !== previousBlock) {
        if (text.length > 0) {
          text += SEPARATOR;
        }
        previousBlock = block;
      }
      nodes.push({ node, start: text.length, end: text.length + node.data.length });
      text += node.data;
    }
    return { text, nodes };
  }

  // A literal search for `query`: regex syntax is escaped, and any run of whitespace matches any
  // run of whitespace (a soft line break renders as a space). Case-insensitive unless asked.
  function pattern(query, caseSensitive) {
    const parts = query.split(/\s+/u).map((part) => part.replace(/[\\^$.*+?()[\]{}|/]/gu, "\\$&"));
    return new RegExp(parts.join("\\s+"), caseSensitive ? "gu" : "giu");
  }

  // The index of the text node containing `offset`, searching forward from `from`. An end
  // offset belongs to the node it ends, not the next one.
  function nodeIndex(nodes, offset, from, isEnd) {
    for (let index = from; index < nodes.length; index += 1) {
      const { start, end } = nodes[index];
      if (isEnd ? offset > start && offset <= end : offset >= start && offset < end) {
        return index;
      }
    }
    return -1;
  }

  function findRanges(query, caseSensitive) {
    const { text, nodes } = collectText(scope());
    const ranges = [];
    let limited = false;
    let from = 0;
    for (const match of text.matchAll(pattern(query, caseSensitive))) {
      if (match[0].length === 0) {
        continue;
      }
      if (ranges.length === MAXIMUM_MATCHES) {
        limited = true;
        break;
      }
      const startIndex = nodeIndex(nodes, match.index, from, false);
      const endIndex = startIndex < 0 ? -1 : nodeIndex(nodes, match.index + match[0].length, startIndex, true);
      if (endIndex < 0) {
        continue;
      }
      const range = document.createRange();
      range.setStart(nodes[startIndex].node, match.index - nodes[startIndex].start);
      range.setEnd(nodes[endIndex].node, match.index + match[0].length - nodes[endIndex].start);
      ranges.push(range);
      from = startIndex;
    }
    return { ranges, limited };
  }

  function setHighlight(name, ranges, priority) {
    if (typeof Highlight !== "function" || globalThis.CSS?.highlights === undefined) {
      return;
    }
    if (ranges.length === 0) {
      CSS.highlights.delete(name);
      return;
    }
    const highlight = new Highlight(...ranges);
    highlight.priority = priority;
    CSS.highlights.set(name, highlight);
  }

  // The first match at or below the top of the viewport (or the first match).
  function firstVisible() {
    let low = 0;
    let high = matches.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (matches[middle].getBoundingClientRect().bottom > 0) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low < matches.length ? low : 0;
  }

  // The first match starting at or after `anchor` (a previous current match), or -1.
  function firstFrom(anchor) {
    if (anchor === null || !anchor.startContainer.isConnected) {
      return -1;
    }
    return matches.findIndex((range) => range.compareBoundaryPoints(Range.START_TO_START, anchor) >= 0);
  }

  // Scrolls `range` into view: horizontally inside overflowing blocks (code, tables), then the
  // page, centering it when it isn't already fully visible.
  function reveal(range) {
    let rect = range.getBoundingClientRect();
    for (let element = range.startContainer.parentElement; element !== null && element !== document.body;
      element = element.parentElement) {
      if (element.scrollWidth > element.clientWidth) {
        const box = element.getBoundingClientRect();
        if (rect.left < box.left || rect.right > box.right) {
          element.scrollLeft += rect.left - box.left - (box.width - rect.width) / 2;
          rect = range.getBoundingClientRect();
        }
      }
    }
    if (rect.top < 0 || rect.bottom > window.innerHeight) {
      window.scrollTo(window.scrollX, window.scrollY + rect.top - (window.innerHeight - rect.height) / 2);
    }
  }

  // Finds `query` and highlights every match, with no current match yet. Returns the count,
  // whether counting stopped at the limit, and the match to start at: the first at or after the
  // current match when `fromCurrent` (typing extends a search in place), else the first in view.
  function search(query, caseSensitive, fromCurrent) {
    const anchor = fromCurrent && current >= 0 ? matches[current] : null;
    clear(false);
    const text = typeof query === "string" ? query.replaceAll(SEPARATOR, "").slice(0, MAXIMUM_QUERY_LENGTH) : "";
    if (text.trim().length === 0) {
      return { count: 0, limited: false, first: 0 };
    }
    const found = findRanges(text, caseSensitive === true);
    matches = found.ranges;
    setHighlight(ALL, matches, 0);
    const fromAnchor = firstFrom(anchor);
    const first = matches.length === 0 ? 0 : fromAnchor >= 0 ? fromAnchor : firstVisible();
    return { count: matches.length, limited: found.limited, first };
  }

  // Makes match `index` the current one and, when `scroll`, scrolls it into view.
  function select(index, scroll) {
    if (!Number.isInteger(index) || index < 0 || index >= matches.length) {
      return false;
    }
    current = index;
    setHighlight(CURRENT, [matches[index]], 1);
    if (scroll === true) {
      reveal(matches[index]);
    }
    return true;
  }

  // Removes the highlights. With `selectCurrent`, the current match becomes the text selection
  // (as in Safari, so closing the find bar leaves it selected for copying).
  function clear(selectCurrent) {
    if (selectCurrent === true && current >= 0 && current < matches.length) {
      const selection = document.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(matches[current].cloneRange());
    }
    matches = [];
    current = -1;
    setHighlight(ALL, [], 0);
    setHighlight(CURRENT, [], 1);
    return true;
  }

  // The selected text, for Use Selection for Find.
  function selectionText() {
    return (document.getSelection()?.toString() ?? "").slice(0, MAXIMUM_QUERY_LENGTH);
  }

  // Jump to Selection: scrolls the current match (while the find bar is open) or else the
  // selected text into view. Returns false when there is neither.
  function revealSelection() {
    let range = current >= 0 && current < matches.length ? matches[current] : null;
    if (range === null) {
      const selection = document.getSelection();
      if (selection === null || selection.rangeCount === 0 || selection.isCollapsed) {
        return false;
      }
      range = selection.getRangeAt(0);
    }
    if (!range.startContainer.isConnected) {
      return false;
    }
    reveal(range);
    return true;
  }

  globalThis.mdvFind = Object.freeze({ search, select, clear, selectionText, revealSelection });
})();
