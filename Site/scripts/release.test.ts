import { describe, expect, it } from "vite-plus/test";
import { LATEST_RELEASE_URL, isSignedAppcast, latestAppcast, redirectsOf } from "./release.ts";

const ASSET_URL = "https://github.com/itspriddle/peep/releases/download/v0.1.0/appcast.xml";

// The shape generate_appcast writes (trimmed).
const SIGNED = `<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel><title>Peep</title></channel>
</rss>
<!-- sparkle-signatures:
edSignature: gVb2t6mUFCYGM/fcC55ajDU4PQHr95p5iD7X6g1+AKvpk70/Tnq1vfBz1NkGFBkz9WSIx141q+inpJ2mgHFSDQ==
length: 2067
-->
`;
const UNSIGNED = SIGNED.slice(0, SIGNED.indexOf("<!-- sparkle-signatures:"));

function json(body: unknown, status = 200): Response {
    return new Response(JSON.stringify(body), { status });
}

function fakeFetch(routes: Record<string, () => Response>) {
    const requests: { url: string; init?: RequestInit }[] = [];
    const fetchFn = async (url: string, init?: RequestInit) => {
        requests.push({ url, init });
        const route = routes[url];
        return route ? route() : new Response("not found", { status: 404 });
    };
    return { fetchFn, requests };
}

function release(assets: { name: string; browser_download_url: string }[]) {
    return () => json({ tag_name: "v0.1.0", assets });
}

describe("isSignedAppcast", () => {
    it("accepts generate_appcast's signed feed", () => {
        expect(isSignedAppcast(SIGNED)).toBe(true);
    });

    it("refuses an unsigned feed, HTML, and an empty body", () => {
        expect(isSignedAppcast(UNSIGNED)).toBe(false);
        expect(isSignedAppcast("<!doctype html><html></html>")).toBe(false);
        expect(isSignedAppcast("")).toBe(false);
    });
});

describe("latestAppcast", () => {
    it("returns null when nothing has been released", async () => {
        const { fetchFn } = fakeFetch({});
        await expect(latestAppcast(fetchFn)).resolves.toBeNull();
    });

    it("downloads the latest release's signed appcast", async () => {
        const { fetchFn, requests } = fakeFetch({
            [LATEST_RELEASE_URL]: release([
                { name: "Peep-0.1.0.dmg", browser_download_url: "unused" },
                { name: "appcast.xml", browser_download_url: ASSET_URL },
            ]),
            [ASSET_URL]: () => new Response(SIGNED),
        });
        await expect(latestAppcast(fetchFn)).resolves.toBe(SIGNED);
        expect(requests.map((request) => request.url)).toEqual([LATEST_RELEASE_URL, ASSET_URL]);
    });

    it("sends the token to the API only", async () => {
        const { fetchFn, requests } = fakeFetch({
            [LATEST_RELEASE_URL]: release([
                { name: "appcast.xml", browser_download_url: ASSET_URL },
            ]),
            [ASSET_URL]: () => new Response(SIGNED),
        });
        await latestAppcast(fetchFn, "t0ken");
        const apiHeaders = requests[0]?.init?.headers as Record<string, string>;
        expect(apiHeaders.Authorization).toBe("Bearer t0ken");
        expect(requests[1]?.init).toBeUndefined();
    });

    it("fails when the release has no appcast", async () => {
        const { fetchFn } = fakeFetch({
            [LATEST_RELEASE_URL]: release([{ name: "Peep-0.1.0.dmg", browser_download_url: "x" }]),
        });
        await expect(latestAppcast(fetchFn)).rejects.toThrow("release v0.1.0 has no appcast.xml");
    });

    it("fails when the asset isn't a signed appcast", async () => {
        const { fetchFn } = fakeFetch({
            [LATEST_RELEASE_URL]: release([
                { name: "appcast.xml", browser_download_url: ASSET_URL },
            ]),
            [ASSET_URL]: () => new Response(UNSIGNED),
        });
        await expect(latestAppcast(fetchFn)).rejects.toThrow("isn't a signed appcast");
    });

    it("fails on an API error rather than shipping no appcast", async () => {
        const { fetchFn } = fakeFetch({
            [LATEST_RELEASE_URL]: () => json({ message: "rate limited" }, 403),
        });
        await expect(latestAppcast(fetchFn)).rejects.toThrow("HTTP 403");
    });

    it("fails when the download fails", async () => {
        const { fetchFn } = fakeFetch({
            [LATEST_RELEASE_URL]: release([
                { name: "appcast.xml", browser_download_url: ASSET_URL },
            ]),
            [ASSET_URL]: () => new Response("gone", { status: 502 }),
        });
        await expect(latestAppcast(fetchFn)).rejects.toThrow("HTTP 502");
    });
});

describe("latestAppcast asset URLs", () => {
    it("refuses an appcast that isn't a release download of this repository", async () => {
        const elsewhere = "https://example.com/appcast.xml";
        const { fetchFn, requests } = fakeFetch({
            [LATEST_RELEASE_URL]: release([
                { name: "appcast.xml", browser_download_url: elsewhere },
            ]),
            [elsewhere]: () => new Response(SIGNED),
        });
        await expect(latestAppcast(fetchFn)).rejects.toThrow("isn't a https://github.com/");
        expect(requests.map((request) => request.url)).toEqual([LATEST_RELEASE_URL]);
    });
});

describe("redirectsOf", () => {
    const DMG_URL = "https://github.com/itspriddle/peep/releases/download/v0.1.0/Peep-0.1.0.dmg";

    it("redirects /download to the release's DMG", () => {
        const redirects = redirectsOf({
            tag_name: "v0.1.0",
            assets: [
                { name: "appcast.xml", browser_download_url: ASSET_URL },
                { name: "Peep-0.1.0.dmg", browser_download_url: DMG_URL },
            ],
        });
        expect(redirects).toBe(`/download ${DMG_URL} 302\n`);
    });

    it("fails when the release has no DMG for its version", () => {
        expect(() =>
            redirectsOf({
                tag_name: "v0.1.1",
                assets: [{ name: "Peep-0.1.0.dmg", browser_download_url: DMG_URL }],
            }),
        ).toThrow("release v0.1.1 has no Peep-0.1.1.dmg");
    });

    it("fails on a tag that isn't vX.Y.Z", () => {
        expect(() => redirectsOf({ tag_name: "nightly", assets: [] })).toThrow("isn't vX.Y.Z");
    });

    it("refuses a DMG that isn't a release download of this repository", () => {
        expect(() =>
            redirectsOf({
                tag_name: "v0.1.0",
                assets: [
                    { name: "Peep-0.1.0.dmg", browser_download_url: "https://example.com/x.dmg" },
                ],
            }),
        ).toThrow("isn't a https://github.com/");
    });
});
