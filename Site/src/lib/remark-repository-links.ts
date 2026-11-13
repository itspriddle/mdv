// Rewrites relative links in Markdown from the repository's docs/ folder. On GitHub they
// resolve against the repository; on the site they would 404. A link to a published doc goes to
// its page, anything else to the file on GitHub. Absolute URLs and #fragments are unchanged.
import { posix } from "node:path";
import { fileURLToPath } from "node:url";
import { publishedDocs, repository } from "./repository.ts";

interface MarkdownNode {
    type: string;
    url?: string;
    children?: MarkdownNode[];
}

interface MarkdownFile {
    path?: string;
    cwd: string;
}

// This file is Site/src/lib/; the repository root is three folders up.
const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));

const absolute = /^[a-z][a-z0-9+.-]*:|^\/\/|^#/i;

export function repositoryURL(url: string, documentPath: string): string {
    if (url === "" || absolute.test(url)) {
        return url;
    }
    const hashIndex = url.indexOf("#");
    const path = hashIndex === -1 ? url : url.slice(0, hashIndex);
    const fragment = hashIndex === -1 ? "" : url.slice(hashIndex);
    const resolved = posix.normalize(posix.join(posix.dirname(documentPath), path));
    if (resolved.startsWith("../") || resolved === "..") {
        return url;
    }
    const page = publishedDocs[resolved];
    return page === undefined ? `${repository}/blob/main/${resolved}${fragment}` : page + fragment;
}

function visit(node: MarkdownNode, documentPath: string): void {
    if ((node.type === "link" || node.type === "definition") && node.url !== undefined) {
        node.url = repositoryURL(node.url, documentPath);
    }
    for (const child of node.children ?? []) {
        visit(child, documentPath);
    }
}

// The document's path from the repository root, or undefined for Markdown outside it.
function repositoryPath(file: MarkdownFile): string | undefined {
    if (file.path === undefined) {
        return undefined;
    }
    const path = posix.relative(repositoryRoot, posix.resolve(file.cwd, file.path));
    return path.startsWith("docs/") ? path : undefined;
}

export function remarkRepositoryLinks() {
    return (tree: MarkdownNode, file: MarkdownFile): void => {
        const path = repositoryPath(file);
        if (path !== undefined) {
            visit(tree, path);
        }
    };
}
