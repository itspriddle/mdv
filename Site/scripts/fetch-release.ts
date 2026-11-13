// Writes what the site publishes from the latest GitHub Release into the build output folder
// (scripts/release.ts): the signed appcast (appcast.xml) and the /download redirect
// (_redirects). Before the first release it removes both, so each is a real 404. Run by
// `vp run build` after the bundle is built.
//
//   node scripts/fetch-release.ts dist
//
// GITHUB_TOKEN, if set, is sent to the GitHub API only (rate limit); never needed.
import { rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import process from "node:process";
import { APPCAST_ASSET, appcastOf, latestRelease, redirectsOf } from "./release.ts";

const output = process.argv[2];
if (!output) {
    console.error("usage: node scripts/fetch-release.ts OUTPUT_FOLDER");
    process.exit(64);
}

const appcastPath = join(output, APPCAST_ASSET);
const redirectsPath = join(output, "_redirects");

const release = await latestRelease(fetch, process.env.GITHUB_TOKEN || undefined);
if (release === null) {
    await rm(appcastPath, { force: true });
    await rm(redirectsPath, { force: true });
    console.log(`fetch-release: no published release yet; no ${APPCAST_ASSET} or _redirects`);
} else {
    // Both are checked before either is written, so a bad release never ships half of it.
    const xml = await appcastOf(fetch, release);
    const redirects = redirectsOf(release);
    await writeFile(appcastPath, xml);
    await writeFile(redirectsPath, redirects);
    console.log(
        `fetch-release: ${release.tag_name}: wrote ${appcastPath} (${Buffer.byteLength(xml)} bytes) and ${redirectsPath}`,
    );
}
