// mdv scroll position: reports the reading position to the app while the document scrolls, so
// the outline sidebar can highlight the current section.
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The `scrollPosition` message handler is registered in that world only, so the
// page can neither see it nor post to it. The message is a number: the source line the
// outline reads its current section at (`mdv.sectionSourceLine()`, DocumentBridge.js).
//
// Reports are debounced: one after scrolling pauses for DELAY ms, and at least one every
// MAX_WAIT ms during a long scroll, so the highlight follows along without a message per frame.
"use strict";

(() => {
  const handler = globalThis.webkit?.messageHandlers?.scrollPosition;
  if (handler === undefined) {
    return;
  }

  const DELAY = 80;
  const MAX_WAIT = 200;

  let timer = null;
  let firstEvent = 0;

  function report() {
    timer = null;
    const bridge = globalThis.mdv;
    if (bridge === undefined) {
      return;
    }
    handler.postMessage(bridge.sectionSourceLine());
  }

  window.addEventListener(
    "scroll",
    () => {
      const now = performance.now();
      if (timer === null) {
        firstEvent = now;
      } else {
        clearTimeout(timer);
      }
      const wait = Math.max(0, Math.min(DELAY, firstEvent + MAX_WAIT - now));
      timer = setTimeout(report, wait);
    },
    { passive: true },
  );
})();
