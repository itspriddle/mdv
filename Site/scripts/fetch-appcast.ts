// Writes the latest release's signed appcast to the given path (dist/appcast.xml), or removes
// it when nothing has been released yet. Run by `vp run build` after the bundle is built.
//
//   node scripts/fetch-appcast.ts dist/appcast.xml
//
// GITHUB_TOKEN, if set, is sent to the GitHub API only (rate limit); never needed.
import { rm, writeFile } from "node:fs/promises";
import process from "node:process";
import { APPCAST_ASSET, latestAppcast } from "./appcast.ts";

const output = process.argv[2];
if (!output) {
    console.error("usage: node scripts/fetch-appcast.ts OUTPUT");
    process.exit(64);
}

const xml = await latestAppcast(fetch, process.env.GITHUB_TOKEN || undefined);
if (xml === null) {
    await rm(output, { force: true });
    console.log(`fetch-appcast: no published release yet; no ${APPCAST_ASSET}`);
} else {
    await writeFile(output, xml);
    console.log(`fetch-appcast: wrote ${output} (${Buffer.byteLength(xml)} bytes)`);
}
