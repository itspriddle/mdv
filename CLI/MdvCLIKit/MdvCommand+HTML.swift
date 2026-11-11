import Foundation
import MdvCore

// Headless output: `--html`, `--fragment`, `--output`.

extension MdvCommand {
    /// Reads and renders every input before writing anything, so a bad input leaves no partial
    /// output (and no `--output` file).
    func writeHTML(in environment: CLIEnvironment) async throws(CLIError) {
        let sources = input.sources
        var text = ""
        for source in sources {
            let document = try InputDocument.read(source, in: environment)
            text += try await renderHTML(document, in: environment)
        }
        try output.destination.write(text, inputs: sources, in: environment)
    }

    /// One input's output: the page (or fragment) and a trailing newline.
    func renderHTML(_ document: InputDocument, in environment: CLIEnvironment) async throws(CLIError) -> String {
        let markdown = try await preprocessor.preprocess(document)
        var options = RenderOptions()
        themeFlavor.apply(to: &options)
        renderFlags.apply(to: &options)
        let renderer = renderFlags.renderer(options: options, for: document.source)
        let rendered = renderer.render(markdown)
        renderFlags.report(rendered, for: document.source, in: environment)
        if output.fragment {
            return rendered.html.hasSuffix("\n") || rendered.html.isEmpty ? rendered.html : rendered.html + "\n"
        }
        let page = HTMLDocument(
            title: rendered.title ?? document.source.fallbackTitle,
            body: rendered.html,
            theme: try themeFlavor.theme(for: rendered, in: environment))
        return page.html + "\n"
    }
}
