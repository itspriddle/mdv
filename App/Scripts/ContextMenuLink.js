// mdv context menu link: remembers the link the context menu was opened on, for the app's
// "Copy Link" (#42), which copies a file: URL instead of WebKit's internal mdv-doc: URL.
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `mdvContextMenu`. The `contextmenu` event fires
// before the menu opens, so the link is recorded before any menu item can be chosen.
"use strict";

(() => {
  let href = "";

  // Listeners on the document survive in-place content swaps (`mdv.replaceContent`).
  document.addEventListener(
    "contextmenu",
    (event) => {
      const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
      href = link !== null && typeof link.href === "string" ? link.href : "";
    },
    true,
  );

  // The resolved `href` of the link under the last context menu, or "" for none.
  function link() {
    return href;
  }

  globalThis.mdvContextMenu = Object.freeze({ link });
})();
