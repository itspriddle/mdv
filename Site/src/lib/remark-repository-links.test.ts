import { describe, expect, it } from "vite-plus/test";
import { repositoryURL } from "./remark-repository-links.ts";

const blob = "https://github.com/itspriddle/peep/blob/main";

describe("repositoryURL", () => {
    it("sends a sibling file to GitHub", () => {
        expect(repositoryURL("example-theme.css", "docs/THEMES.md")).toBe(
            `${blob}/docs/example-theme.css`,
        );
    });

    it("resolves parent paths and keeps the fragment", () => {
        expect(repositoryURL("../README.md#per-document-settings", "docs/THEMES.md")).toBe(
            `${blob}/README.md#per-document-settings`,
        );
        expect(repositoryURL("../Sources/PeepCore/Themes", "docs/THEMES.md")).toBe(
            `${blob}/Sources/PeepCore/Themes`,
        );
    });

    it("sends a published doc to its page", () => {
        expect(repositoryURL("THEMES.md#wiki-links", "docs/VISION.md")).toBe("/themes#wiki-links");
    });

    it("leaves absolute URLs and fragments alone", () => {
        for (const url of [
            "https://highlightjs.org/",
            "mailto:x@example.com",
            "#quick-start",
            "//cdn",
        ]) {
            expect(repositoryURL(url, "docs/THEMES.md")).toBe(url);
        }
    });

    it("leaves paths outside the repository alone", () => {
        expect(repositoryURL("../../etc/passwd", "docs/THEMES.md")).toBe("../../etc/passwd");
    });
});
