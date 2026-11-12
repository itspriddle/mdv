// Peep scroll position: reports the reading position (the source line at the top of the
// viewport, `peep.currentSourceLine()`) to the app after the page scrolls, so window
// restoration can save it without waiting on an async bridge call at quit.
//
// Runs only in the app's isolated content world ("peep", see AppScripts.swift); page JavaScript
// is disabled. The `scrollPosition` message handler is registered in that world only. The
// message is a number; the app validates it and uses it only as a scroll position.
"use strict";

(() => {
  const handler = globalThis.webkit?.messageHandlers?.scrollPosition;
  if (handler === undefined) {
    return;
  }

  // At most one report per interval while scrolling; the last one runs after scrolling stops,
  // so the final position is always reported.
  const INTERVAL_MS = 250;
  let pending = false;

  function report() {
    pending = false;
    const line = globalThis.peep?.currentSourceLine();
    if (typeof line === "number" && Number.isFinite(line)) {
      handler.postMessage(line);
    }
  }

  window.addEventListener(
    "scroll",
    () => {
      if (!pending) {
        pending = true;
        setTimeout(report, INTERVAL_MS);
      }
    },
    { passive: true },
  );
})();
