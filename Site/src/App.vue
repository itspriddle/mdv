<script setup lang="ts">
import PeepEyes from "./components/PeepEyes.vue";
import PeepWordmark from "./components/PeepWordmark.vue";

const repository = "https://github.com/itspriddle/peep";

// /download redirects to the latest release's DMG (scripts/release.ts writes the rule).
const download = "/download";
const releaseNotes = `${repository}/releases/latest`;
const homebrew = "brew install --cask itspriddle/brews/peep";

const features = [
    {
        title: "Native and fast",
        body: "Swift, SwiftUI and AppKit. Launches instantly and renders large documents without a spinner.",
    },
    {
        title: "Faithful rendering",
        body: "CommonMark and GitHub Flavored Markdown render the way you expect them to on GitHub.",
    },
    {
        title: "Themes are plain CSS",
        body: "Bundled themes are regular stylesheets. A custom theme is a CSS file dropped in a folder.",
    },
    {
        title: "Great from the terminal",
        body: "Opening a file, reading from a pipe, and headless HTML output are first-class, not afterthoughts.",
    },
    {
        title: "Safe by default",
        body: "Markdown files are untrusted input. No remote content, no arbitrary JavaScript, no code execution unless you opt in.",
    },
    {
        title: "Not an editor",
        body: "Peep watches files. Your editor edits them, and the window updates as you save.",
    },
];

const commands = [
    { comment: "open a file in the app", command: "peep README.md" },
    { comment: "pipe anything in", command: "git show HEAD:README.md | peep" },
    { comment: "render HTML to stdout", command: "peep --html README.md > readme.html" },
];
</script>

<template>
    <div class="min-h-svh bg-paper font-sans text-ink dark:bg-ink dark:text-paper">
        <div class="mx-auto max-w-[70rem] px-6">
            <header class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 py-5">
                <a href="/" aria-label="Peep home" class="inline-flex min-h-11 items-center">
                    <PeepWordmark class="h-9 w-auto" />
                </a>
                <nav class="flex flex-wrap items-center gap-x-7 gap-y-1 text-[15px] font-medium">
                    <a href="#features" class="inline-flex min-h-11 items-center hover:underline">
                        Features
                    </a>
                    <a
                        :href="`${repository}/blob/main/docs/THEMES.md`"
                        class="inline-flex min-h-11 items-center hover:underline"
                    >
                        Themes
                    </a>
                    <a :href="repository" class="inline-flex min-h-11 items-center hover:underline">
                        GitHub
                    </a>
                </nav>
            </header>

            <main>
                <section class="flex flex-wrap items-center gap-12 pt-16 pb-18">
                    <div class="flex min-w-0 flex-[1_1_27.5rem] flex-col gap-6">
                        <h1
                            class="text-[clamp(2.75rem,6vw,4.75rem)] leading-[1.04] font-bold tracking-[-0.03em]"
                        >
                            Markdown,
                            <span
                                class="rounded-[10px] bg-highlighter px-[0.12em] whitespace-nowrap text-ink"
                            >
                                at a glance.
                            </span>
                        </h1>
                        <p
                            class="max-w-[34rem] text-xl leading-normal text-neutral-600 dark:text-neutral-300"
                        >
                            Peep is a fast, native Markdown viewer for macOS. Open a file from
                            Finder, the terminal, or a pipe and get a well-typeset document that
                            updates as the file changes.
                        </p>
                        <div class="flex flex-wrap items-center gap-x-4 gap-y-3">
                            <a
                                :href="download"
                                class="inline-flex min-h-12 items-center rounded-xl bg-highlighter px-5.5 font-semibold text-ink hover:brightness-95"
                            >
                                Download for macOS
                            </a>
                            <a
                                :href="repository"
                                class="inline-flex min-h-12 items-center rounded-xl border border-neutral-300 px-5.5 font-semibold hover:bg-black/5 dark:border-white/20 dark:hover:bg-white/10"
                            >
                                View on GitHub
                            </a>
                        </div>
                        <div class="flex max-w-[34rem] flex-col gap-2">
                            <p class="text-sm text-neutral-600 dark:text-neutral-300">
                                Or install with Homebrew:
                            </p>
                            <div
                                class="overflow-x-auto rounded-xl bg-ink px-4.5 py-3 font-mono text-sm text-neutral-100 dark:bg-black/40 dark:ring-1 dark:ring-white/10"
                            >
                                <span class="text-highlighter select-none">$ </span
                                ><span class="whitespace-nowrap">{{ homebrew }}</span>
                            </div>
                        </div>
                        <p class="text-sm text-neutral-500 dark:text-neutral-400">
                            macOS 15 or later. Updates itself.
                            <a :href="releaseNotes" class="underline">Release notes</a>. MIT
                            licensed. No accounts, no cloud.
                        </p>
                    </div>

                    <div class="flex min-w-0 flex-[1_1_27.5rem] flex-col items-center gap-7">
                        <img
                            src="/app-icon.svg"
                            width="168"
                            height="168"
                            alt="Peep app icon"
                            class="drop-shadow-xl"
                        />
                        <div
                            class="flex flex-col gap-2.5 self-stretch overflow-x-auto rounded-2xl bg-ink px-6 py-5.5 font-mono text-sm leading-[1.7] text-neutral-100 dark:bg-black/40 dark:ring-1 dark:ring-white/10"
                        >
                            <div v-for="line in commands" :key="line.command">
                                <div class="whitespace-nowrap text-neutral-400">
                                    # {{ line.comment }}
                                </div>
                                <div class="whitespace-nowrap">
                                    <span class="text-highlighter select-none">$ </span
                                    >{{ line.command }}
                                </div>
                            </div>
                        </div>
                    </div>
                </section>

                <section
                    id="features"
                    class="flex flex-wrap gap-x-10 gap-y-9 border-t border-mist py-14 dark:border-white/10"
                >
                    <div
                        v-for="feature in features"
                        :key="feature.title"
                        class="flex min-w-0 flex-[1_1_17.5rem] flex-col gap-2"
                    >
                        <h2 class="text-lg font-semibold">{{ feature.title }}</h2>
                        <p
                            class="text-[15px] leading-[1.55] text-neutral-600 dark:text-neutral-300"
                        >
                            {{ feature.body }}
                        </p>
                    </div>
                </section>
            </main>

            <footer
                class="flex flex-wrap items-center justify-between gap-x-6 gap-y-3 border-t border-mist pt-6 pb-10 text-sm text-neutral-500 dark:border-white/10 dark:text-neutral-400"
            >
                <div class="flex items-center gap-3">
                    <PeepEyes class="h-5.5 w-auto text-ink dark:text-paper" />
                    <span>peep.now</span>
                </div>
                <div class="flex flex-wrap items-center gap-x-6 gap-y-1">
                    <span>MIT licensed</span>
                    <a :href="repository" class="inline-flex min-h-11 items-center underline">
                        itspriddle/peep
                    </a>
                </div>
            </footer>
        </div>
    </div>
</template>
