// Peep document bridge: scrolling, position, and in-place content swaps for the viewer.
//
// Runs only in the app's isolated content world ("peep", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `peep`. Swift calls these functions with
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

  // The source line at the top of the viewport (or `offset` CSS pixels below it). Line 1 is
  // the top of the page.
  function currentSourceLine(offset = 0) {
    const blocks = annotatedBlocks();
    const viewportTop = window.scrollY + offset;
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

  // How far below the top of the viewport the outline's current section is measured, in CSS
  // pixels, so a heading scrolled to the top (sub-pixel positions included) is in its section.
  const SECTION_OFFSET = 8;

  // The source line the outline's current section is read at (after each ScrollPosition.js
  // report; see DocumentWindowController+Outline.swift).
  //
  // Normally just below the top of the viewport. Sections near the end of a page can't scroll
  // to the top, so over the last viewport height of scrolling the reading line moves down with
  // the scroll position and reaches the bottom of the viewport at the end of the page: each
  // short trailing section becomes current in turn, and the last one at the bottom. A page
  // that doesn't scroll keeps the line at the top.
  function sectionSourceLine() {
    const maximum = maximumScrollY();
    let offset = SECTION_OFFSET;
    if (maximum > 0) {
      const span = Math.min(window.innerHeight, maximum);
      const remaining = Math.max(0, maximum - window.scrollY);
      const progress = 1 - Math.min(1, remaining / span);
      offset += progress * Math.max(0, window.innerHeight - SECTION_OFFSET - 1);
    }
    return currentSourceLine(offset);
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

  // How close to the bottom (in CSS pixels) still counts as "at the bottom".
  const BOTTOM_TOLERANCE = 4;

  function maximumScrollY() {
    return Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
  }

  // The reading position to keep across a content change: the source line at the top of the
  // viewport, and whether the view is scrolled to the bottom of a page taller than the window.
  // A page that fits the window is never "at the bottom", so a short document that grows
  // stays at its top until the reader scrolls down.
  function readingPosition() {
    const maximum = maximumScrollY();
    const atBottom = maximum > 0 && window.scrollY >= maximum - BOTTOM_TOLERANCE;
    return { line: currentSourceLine(), atBottom };
  }

  // Restores a `readingPosition()`: the bottom stays the bottom (log-tail behavior while
  // writing); otherwise the closest block at or before the line, plus the offset into it.
  function restorePosition(position) {
    if (position.atBottom) {
      window.scrollTo(0, maximumScrollY());
    } else {
      scrollToSourceLine(position.line);
    }
  }

  // Restores again once images that hadn't loaded at swap time have their size, unless the
  // reader has scrolled since. Images above the viewport would otherwise push it down.
  function restoreAfterImagesLoad(position) {
    const pending = [...document.images].filter((image) => !image.complete);
    if (pending.length === 0) {
      return;
    }
    let expectedY = window.scrollY;
    const onSettled = () => {
      if (Math.abs(window.scrollY - expectedY) < 1) {
        restorePosition(position);
        expectedY = window.scrollY;
      }
    };
    for (const image of pending) {
      image.addEventListener("load", onSettled, { once: true });
      image.addEventListener("error", onSettled, { once: true });
    }
  }

  // Live reload: swaps in new content and keeps the reading position, all in one script run,
  // so nothing is painted between the swap and the scroll.
  function updateContent(html, title) {
    const position = readingPosition();
    if (!replaceContent(html, title)) {
      return false;
    }
    restorePosition(position);
    restoreAfterImagesLoad(position);
    return true;
  }

  // Replaces the text of one of the page's layer <style> elements in <head> (`id` is a
  // ThemeLayer name, e.g. "peep-user"), keeping the reading position across the reflow. One
  // script run, so nothing is painted in between. Only <head> is searched, so an element in
  // the document body can't stand in for it. Returns whether the element was found.
  function replaceStyle(id, css) {
    if (typeof id !== "string" || typeof css !== "string" || document.head === null) {
      return false;
    }
    const style = [...document.head.querySelectorAll("style")].find((element) => element.id === id);
    if (style === undefined) {
      return false;
    }
    if (style.textContent === css) {
      return true;
    }
    const position = readingPosition();
    style.textContent = css;
    restorePosition(position);
    return true;
  }

  // The most <picture> candidates loaded before printing, and how long printing waits for them.
  const PRINT_PRELOAD_LIMIT = 64;
  const PRINT_PRELOAD_TIMEOUT_MS = 3000;

  // Loads every <picture> candidate (each <source> and the <img>) into this document before
  // printing. Printing evaluates `prefers-color-scheme` as light, so a dark window's pictures
  // switch to their light candidate as the page is printed; one the document never loaded is
  // fetched then, and the print can be drawn before it arrives, putting the dark image on
  // paper. WebKit doesn't load an image twice in one document, so a candidate loaded here is
  // there when the switch happens. Detached images choose from `srcset` and `sizes` as the
  // picture would. Resolves once all have loaded or failed, or after the timeout.
  async function preloadPictureSources() {
    const candidates = [];
    for (const picture of document.querySelectorAll("picture")) {
      for (const element of picture.querySelectorAll("source, img")) {
        if (candidates.length >= PRINT_PRELOAD_LIMIT) {
          break;
        }
        const srcset = element.getAttribute("srcset");
        const src = element.localName === "img" ? element.getAttribute("src") : null;
        if (srcset === null && src === null) {
          continue;
        }
        const image = new Image();
        if (element.hasAttribute("sizes")) {
          image.sizes = element.getAttribute("sizes");
        }
        if (srcset !== null) {
          image.srcset = srcset;
        }
        if (src !== null) {
          image.src = src;
        }
        candidates.push(image.decode().catch(() => null));
      }
    }
    if (candidates.length === 0) {
      return 0;
    }
    const timeout = new Promise((resolve) => setTimeout(resolve, PRINT_PRELOAD_TIMEOUT_MS));
    await Promise.race([Promise.all(candidates), timeout]);
    return candidates.length;
  }

  globalThis.peep = Object.freeze({
    currentSourceLine,
    sectionSourceLine,
    scrollToSourceLine,
    scrollToFirstID,
    replaceContent,
    readingPosition,
    restorePosition,
    updateContent,
    replaceStyle,
    preloadPictureSources,
  });
})();
