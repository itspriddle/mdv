// mdv link hover: reports the link under the pointer (or keyboard focus) to the app, which
// shows where it goes in a status overlay.
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The `linkHover` message handler is registered in that world only, so the page
// can neither see it nor post to it. The message is the link's resolved `href` (a string), or
// "" when no link is hovered; the app treats it as display text and never acts on it (clicks
// go through the navigation policy).
"use strict";

(() => {
  const handler = globalThis.webkit?.messageHandlers?.linkHover;
  if (handler === undefined) {
    return;
  }

  let current = "";

  function hrefFor(node) {
    const link = node instanceof Element ? node.closest("a[href]") : null;
    const href = link === null ? "" : link.href;
    return typeof href === "string" ? href : "";
  }

  function report(href) {
    if (href !== current) {
      current = href;
      handler.postMessage(href);
    }
  }

  // Listeners on the document survive in-place content swaps (`mdv.replaceContent`).
  document.addEventListener("mouseover", (event) => report(hrefFor(event.target)), true);
  document.addEventListener(
    "mouseout",
    (event) => {
      if (event.relatedTarget === null) {
        report("");
      }
    },
    true,
  );
  document.addEventListener("focusin", (event) => report(hrefFor(event.target)), true);
  document.addEventListener("focusout", () => report(""), true);
})();
