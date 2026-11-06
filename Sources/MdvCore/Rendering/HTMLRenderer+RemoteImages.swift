extension HTMLRenderer {
    /// The Markdown images `renderImage` replaces with placeholders, in document order. Images
    /// in an image's alt text are rendered as text, so they aren't visited.
    func blockedMarkdownImages(in root: MarkdownNode) -> [RemoteImage] {
        guard options.remoteImages != .keep else {
            return []
        }
        var blocked: [RemoteImage] = []
        var stack = [root]
        while let node = stack.popLast() {
            if case .image(let source, _) = node.kind {
                if let image = blockedRemoteImage(source) {
                    blocked.append(image)
                }
                continue
            }
            stack.append(contentsOf: node.children.reversed())
        }
        return blocked
    }

    /// The remote image `source` names, when `options.remoteImages` blocks it. Sources cmark's
    /// safe mode blanks (`DangerousURL`, e.g. `file:`) aren't remote: they render as an empty
    /// `src`, as before.
    func blockedRemoteImage(_ source: String) -> RemoteImage? {
        guard options.remoteImages != .keep, !DangerousURL.matches(source), let image = RemoteImage(source: source),
            options.remoteImages.blocks(image)
        else {
            return nil
        }
        return image
    }
}
