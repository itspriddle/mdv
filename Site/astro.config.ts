import { unified } from "@astrojs/markdown-remark";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";
import { remarkRepositoryLinks } from "./src/lib/remark-repository-links.ts";

// Static output only: Cloudflare serves dist/ as plain assets (wrangler.jsonc).
//
// public/_headers sets a strict CSP (script-src 'self', style-src 'self'), so nothing on a page
// may be inline: stylesheets are always files, pages ship no scripts, and code blocks use
// Prism's classes instead of Shiki's inline style attributes.
export default defineConfig({
    site: "https://peep.now",
    output: "static",
    // /themes is dist/themes.html; Workers static assets serve it without the extension.
    trailingSlash: "never",
    // HTML whitespace rules, not Astro 7's default JSX ones, which drop the space at a line
    // break next to an element ("Markdown,<span>at a glance").
    compressHTML: true,
    build: { format: "file", inlineStylesheets: "never" },
    devToolbar: { enabled: false },
    markdown: {
        syntaxHighlight: "prism",
        processor: unified({ remarkPlugins: [remarkRepositoryLinks] }),
    },
    vite: { plugins: [tailwindcss()] },
});
