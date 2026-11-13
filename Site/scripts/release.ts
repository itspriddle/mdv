// What the site publishes from the latest GitHub Release, at build time:
//
// - The Sparkle appcast at https://peep.now/appcast.xml (#83). The release workflow signs it and
//   attaches it to the GitHub Release; every site build copies the latest published release's
//   copy into dist/, so a redeploy re-publishes the same signed file and never an unsigned one.
// - https://peep.now/download, a `_redirects` rule to that release's DMG, so the page's download
//   link follows each release without changing the page.

export const LATEST_RELEASE_URL = "https://api.github.com/repos/itspriddle/peep/releases/latest";
export const APPCAST_ASSET = "appcast.xml";
export const DOWNLOAD_PATH = "/download";

// Release assets are only ever downloaded from here; anything else in the API response is refused.
const DOWNLOAD_PREFIX = "https://github.com/itspriddle/peep/releases/download/";

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

interface ReleaseAsset {
    name: string;
    browser_download_url: string;
}

export interface Release {
    tag_name: string;
    assets: ReleaseAsset[];
}

// A feed signed by generate_appcast or sign_update: XML, an RSS root, and Sparkle's trailing
// signature comment. Anything else (an HTML error page, an unsigned feed) is refused.
export function isSignedAppcast(xml: string): boolean {
    return (
        xml.startsWith("<?xml") &&
        xml.includes("<rss") &&
        /<!-- sparkle-signatures:\s*edSignature: [A-Za-z0-9+/=]+\s+length: \d+\s*-->\s*$/.test(xml)
    );
}

// The latest published release, or null when nothing has been released yet. `token` only raises
// the API rate limit; the release and its assets are public.
export async function latestRelease(fetchFn: Fetch, token?: string): Promise<Release | null> {
    const headers: Record<string, string> = {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    const response = await fetchFn(LATEST_RELEASE_URL, { headers });
    if (response.status === 404) {
        return null;
    }
    if (!response.ok) {
        throw new Error(`${LATEST_RELEASE_URL}: HTTP ${response.status}`);
    }
    return (await response.json()) as Release;
}

// The asset named `name`, whose URL must be under this repository's release downloads.
function asset(release: Release, name: string): ReleaseAsset {
    const found = release.assets.find((candidate) => candidate.name === name);
    if (!found) {
        throw new Error(`release ${release.tag_name} has no ${name}`);
    }
    if (!found.browser_download_url.startsWith(DOWNLOAD_PREFIX)) {
        throw new Error(`release ${release.tag_name}'s ${name} isn't a ${DOWNLOAD_PREFIX} URL`);
    }
    return found;
}

// The release's signed appcast. A release without one is an error.
export async function appcastOf(fetchFn: Fetch, release: Release): Promise<string> {
    const { browser_download_url: url } = asset(release, APPCAST_ASSET);
    const download = await fetchFn(url);
    if (!download.ok) {
        throw new Error(`${url}: HTTP ${download.status}`);
    }
    const xml = await download.text();
    if (!isSignedAppcast(xml)) {
        throw new Error(`release ${release.tag_name}'s ${APPCAST_ASSET} isn't a signed appcast`);
    }
    return xml;
}

// The `_redirects` file: /download to the release's DMG, `Peep-X.Y.Z.dmg` for tag `vX.Y.Z`
// (scripts/package-release names it). 302, so browsers and caches never pin an old release.
export function redirectsOf(release: Release): string {
    const match = /^v(\d+\.\d+\.\d+)$/.exec(release.tag_name);
    if (!match) {
        throw new Error(`release tag ${release.tag_name} isn't vX.Y.Z`);
    }
    const { browser_download_url: url } = asset(release, `Peep-${match[1]}.dmg`);
    return `${DOWNLOAD_PATH} ${url} 302\n`;
}

// The latest published release's appcast, or null when nothing has been released yet (the site
// then serves no appcast, a real 404).
export async function latestAppcast(fetchFn: Fetch, token?: string): Promise<string | null> {
    const release = await latestRelease(fetchFn, token);
    return release === null ? null : appcastOf(fetchFn, release);
}
