// The Sparkle appcast at https://peep.now/appcast.xml (#83). The release workflow signs it and
// attaches it to the GitHub Release; every site build copies the latest published release's
// copy into dist/, so a redeploy re-publishes the same signed file and never an unsigned one.

export const LATEST_RELEASE_URL = "https://api.github.com/repos/itspriddle/peep/releases/latest";
export const APPCAST_ASSET = "appcast.xml";

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

interface ReleaseAsset {
    name: string;
    browser_download_url: string;
}

interface Release {
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

// The latest published release's appcast, or null when nothing has been released yet (the site
// then serves no appcast, a real 404). A release without a signed appcast.xml is an error.
// `token` only raises the API rate limit; the release and its assets are public.
export async function latestAppcast(fetchFn: Fetch, token?: string): Promise<string | null> {
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
    const release = (await response.json()) as Release;
    const asset = release.assets.find((candidate) => candidate.name === APPCAST_ASSET);
    if (!asset) {
        throw new Error(`release ${release.tag_name} has no ${APPCAST_ASSET}`);
    }
    const download = await fetchFn(asset.browser_download_url);
    if (!download.ok) {
        throw new Error(`${asset.browser_download_url}: HTTP ${download.status}`);
    }
    const xml = await download.text();
    if (!isSignedAppcast(xml)) {
        throw new Error(`release ${release.tag_name}'s ${APPCAST_ASSET} isn't a signed appcast`);
    }
    return xml;
}
