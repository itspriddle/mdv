// mdv context menu link: remembers the link the context menu was opened on, for the app's
// "Copy Link" (#42), which copies a file: URL instead of WebKit's internal mdv-doc: URL. Also
// reports the link and image under the menu to the app, which replaces Share and Copy Image
// for local ones, and draws that image as a PNG for Copy Image (decoding stays in WebKit).
//
// Runs only in the app's isolated content world ("mdv", see AppScripts.swift); page JavaScript
// is disabled. The page cannot see or call `mdvContextMenu`, and the `contextMenuTarget` message
// handler is registered in that world only. The `contextmenu` event fires before the menu opens,
// and the message is sent before WebKit asks the app to show the menu, so both are recorded
// before any menu item can be chosen.
"use strict";

(() => {
  const handler = globalThis.webkit?.messageHandlers?.contextMenuTarget;
  let href = "";
  let image = null;

  function resolved(element, attribute) {
    const value = element === null ? "" : element[attribute];
    return typeof value === "string" ? value : "";
  }

  // Listeners on the document survive in-place content swaps (`mdv.replaceContent`).
  document.addEventListener(
    "contextmenu",
    (event) => {
      const target = event.target instanceof Element ? event.target : null;
      href = resolved(target === null ? null : target.closest("a[href]"), "href");
      image = target instanceof HTMLImageElement ? target : null;
      handler?.postMessage({ link: href, image: resolved(image, "currentSrc") });
    },
    true,
  );

  // The resolved `href` of the link under the last context menu, or "" for none.
  function link() {
    return href;
  }

  // The pixel size to draw `element` at: its natural size, or for an SVG (which scales without
  // loss) or an image without one, its rendered size at the screen's scale if that is larger.
  function drawingSize(element) {
    const scale = window.devicePixelRatio || 1;
    const rendered = [Math.round(element.width * scale), Math.round(element.height * scale)];
    const natural = [element.naturalWidth, element.naturalHeight];
    const isSVG = /\.svg$/i.test(new URL(element.currentSrc).pathname);
    if (natural[0] === 0 || natural[1] === 0 || (isSVG && rendered[0] > natural[0])) {
      return rendered;
    }
    return natural;
  }

  // The image under the last context menu as a PNG data URL, at most `maximumSide` pixels a
  // side; "" when there is none, it isn't loaded, or it can't be drawn.
  function imagePNG(maximumSide) {
    if (image === null || !image.isConnected || !image.complete || image.currentSrc === "") {
      return "";
    }
    let [width, height] = drawingSize(image);
    if (!(width > 0 && height > 0)) {
      return "";
    }
    const fit = Math.min(1, maximumSide / Math.max(width, height));
    width = Math.max(1, Math.round(width * fit));
    height = Math.max(1, Math.round(height * fit));
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (context === null) {
      return "";
    }
    try {
      context.drawImage(image, 0, 0, width, height);
      return canvas.toDataURL("image/png");
    } catch {
      return "";
    }
  }

  globalThis.mdvContextMenu = Object.freeze({ link, imagePNG });
})();
