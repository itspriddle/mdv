// mdv document bridge: scrolling, position, and in-place content swaps for the viewer.
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `mdv`. Swift calls these functions with
// callAsyncJavaScript and passes every value as an argument, never as script source.
//
// Positions are source lines, from the renderer's `data-source-line` attributes (1-based lines
// in the original file; see HTMLRenderer+SourceLines.swift). Fractional lines interpolate
// between the tops of neighboring annotated blocks, so a position inside a long paragraph or
// code block survives a round trip.
"use strict";

(() => {
  const ATTRIBUTE = "data-source-line";

  // Annotated blocks in document order. Lines never decrease before the footnotes section;
  // footnote items defined earlier in the file would go back, so the list stops there.
  function annotatedBlocks() {
    const blocks = [];
    let previous = 0;
    for (const element of document.querySelectorAll(`[${ATTRIBUTE}]`)) {
      const line = Number.parseInt(element.getAttribute(ATTRIBUTE), 10);
      if (!Number.isFinite(line)) {
        continue;
      }
      if (line < previous) {
        break;
      }
      blocks.push({ element, line });
      previous = line;
    }
    return blocks;
  }

  function documentTop(element) {
    return element.getBoundingClientRect().top + window.scrollY;
  }

  // The source line at the top of the viewport. Line 1 is the top of the page.
  function currentSourceLine() {
    const blocks = annotatedBlocks();
    const viewportTop = window.scrollY;
    // A virtual block for line 1 at the top of the page covers frontmatter and padding.
    let lower = { line: 1, top: 0 };
    let upper = null;
    for (const block of blocks) {
      const top = documentTop(block.element);
      if (top <= viewportTop) {
        lower = { line: block.line, top };
      } else if (block.line > lower.line) {
        upper = { line: block.line, top };
        break;
      }
    }
    if (upper === null || upper.top <= lower.top) {
      return lower.line;
    }
    const fraction = Math.min(1, Math.max(0, (viewportTop - lower.top) / (upper.top - lower.top)));
    return lower.line + fraction * (upper.line - lower.line);
  }

  // Scrolls so `line` is at the top of the viewport. Lines before the first block scroll to
  // the top of the page.
  function scrollToSourceLine(line) {
    let lower = { line: 1, top: 0 };
    let upper = null;
    for (const block of annotatedBlocks()) {
      if (block.line <= line) {
        lower = { line: block.line, top: documentTop(block.element) };
      } else {
        upper = { line: block.line, top: documentTop(block.element) };
        break;
      }
    }
    let y = lower.top;
    if (upper !== null && upper.line > lower.line) {
      y += ((line - lower.line) / (upper.line - lower.line)) * (upper.top - lower.top);
    }
    if (line <= 1) {
      y = 0;
    }
    window.scrollTo(0, Math.max(0, y));
    return true;
  }

  // Scrolls to the first element whose id is in `ids`, tried in order (Swift builds the list
  // from a link's fragment: raw, percent-decoded, and with the `user-content-` prefix raw HTML
  // ids get). Returns whether one was found.
  function scrollToFirstID(ids) {
    if (!Array.isArray(ids)) {
      return false;
    }
    for (const id of ids) {
      const target = typeof id === "string" ? document.getElementById(id) : null;
      if (target !== null) {
        target.scrollIntoView({ block: "start" });
        return true;
      }
    }
    return false;
  }

  // Replaces the rendered body and title of the loaded page in place, keeping the stylesheet
  // and scroll position. `html` is renderer output; parsing it here runs no script (scripts
  // inserted by innerHTML never execute, and page JavaScript is off for inline handlers).
  function replaceContent(html, title) {
    const article = document.querySelector("article.markdown-body");
    if (article === null) {
      return false;
    }
    article.innerHTML = html;
    document.title = title;
    return true;
  }

  globalThis.mdv = Object.freeze({
    currentSourceLine,
    scrollToSourceLine,
    scrollToFirstID,
    replaceContent,
  });
})();
