import { glob } from "astro/loaders";
import { defineCollection } from "astro:content";

// Pages rendered from the repository's docs/ folder, which stays the one source (the app's
// tests read docs/THEMES.md). List each file: the site never publishes the whole folder.
const docs = defineCollection({
    loader: glob({ base: "../docs", pattern: ["THEMES.md"] }),
});

export const collections = { docs };
