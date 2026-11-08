// Wiki link rendering for `HTMLRenderer` (#53).

extension HTMLRenderer {
    /// `<a class="wikilink" href="…">` for a found page (the destination is already
    /// percent-encoded by `WikiLinks`, and goes through `HTMLOutput.url` like any link), or
    /// `<a class="wikilink wikilink-missing">` with no `href` for a missing one, so it can't
    /// navigate anywhere. The label (the node's children) is written as escaped text.
    func renderWikiLinkStart(_ link: WikiLink, into output: inout HTMLOutput) {
        guard let destination = link.destination else {
            output.raw("<a class=\"wikilink wikilink-missing\">")
            return
        }
        output.raw("<a class=\"wikilink\" href=\"")
        output.url(destination)
        output.raw("\">")
    }
}
