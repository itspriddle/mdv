import Observation
import PeepCore

/// One window's remote image opt-in (#20). Remote images are blocked until the user chooses
/// Load in the remote images bar; the choice covers this window only, lasts until it closes
/// (reloads of the same document keep it), and is never saved.
@MainActor
@Observable
final class RemoteImageOptIn {
    /// The user chose to load `https:` images in this window.
    private(set) var isAllowed = false

    func allow() {
        isAllowed = true
    }

    /// The bar's summary for `page`, or `nil` when there is nothing to offer: the window opted
    /// in already, or no blocked image would load (none, or only cleartext `http:` ones).
    func bar(for page: RenderedPage?) -> RemoteImageSummary? {
        guard !isAllowed, let page else {
            return nil
        }
        let summary = RemoteImageSummary(blocked: page.blockedRemoteImages)
        return summary.loadableCount > 0 ? summary : nil
    }
}

/// What the remote images bar says about a page's blocked images.
struct RemoteImageSummary: Equatable {
    /// Blocked images that would load after opting in (`https:`).
    let loadableCount: Int
    /// Distinct hosts of those images, in document order.
    let hosts: [String]

    /// Hosts named before "and N more".
    static let maximumNamedHosts = 3

    init(blocked: [RemoteImage]) {
        let loadable = blocked.filter(\.isHTTPS)
        loadableCount = loadable.count
        var seen: Set<String> = []
        hosts = loadable.map(\.host).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// e.g. "3 images from img.shields.io and github.com".
    var detail: String {
        let images = loadableCount == 1 ? "1 image" : "\(loadableCount) images"
        guard !hosts.isEmpty else {
            return images
        }
        var named = Array(hosts.prefix(Self.maximumNamedHosts))
        let more = hosts.count - named.count
        if more > 0 {
            named.append(more == 1 ? "1 more" : "\(more) more")
        }
        let list =
            switch named.count {
            case 1: named[0]
            case 2: "\(named[0]) and \(named[1])"
            default: named.dropLast().joined(separator: ", ") + ", and " + (named.last ?? "")
            }
        return "\(images) from \(list)"
    }
}
