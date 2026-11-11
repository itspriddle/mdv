import Darwin
import Foundation

// MARK: - Privileged scripts

extension CommandLineToolInstaller {
    /// The exit status the privileged scripts use when the path holds something they won't touch.
    static let refusedStatus: Int32 = 3

    /// Run as root by `/bin/sh -c` with one or more triples of arguments: the target, the link
    /// path, and the destination of the link it may replace (empty: only when nothing is
    /// there). It first checks every path and refuses (status 3, nothing changed) anything else
    /// at one, including a link to a folder (which `mv` would move into); then it makes the
    /// links. Never edited at run time: values reach it only as arguments.
    static let privilegedInstallScript = """
        set -eu
        count=$(($# / 3)) checked=0
        while [ "$checked" -lt "$count" ]; do
          if [ -L "$2" ]; then
            [ -n "$3" ] && [ "$(/usr/bin/readlink "$2")" = "$3" ] && [ ! -d "$2" ] || exit 3
          elif [ -e "$2" ]; then
            exit 3
          fi
          set -- "$@" "$1" "$2" "$3"
          shift 3
          checked=$((checked + 1))
        done
        while [ "$#" -ge 3 ]; do
          target=$1 link=$2
          shift 3
          folder=$(/usr/bin/dirname "$link")
          /bin/mkdir -p "$folder"
          temporary="$folder/.mdv-install-$$"
          /bin/ln -s "$target" "$temporary"
          /bin/mv -f "$temporary" "$link" || { /bin/rm -f "$temporary"; exit 1; }
        done
        """

    /// Run as root by `/bin/sh -c` with one or more pairs of arguments: a link path and the
    /// destination it must have. It removes only those symbolic links, and refuses (status 3,
    /// nothing removed) when any path is anything else.
    static let privilegedUninstallScript = """
        set -eu
        count=$(($# / 2)) checked=0
        while [ "$checked" -lt "$count" ]; do
          [ -L "$1" ] && [ "$(/usr/bin/readlink "$1")" = "$2" ] || exit 3
          set -- "$@" "$1" "$2"
          shift 2
          checked=$((checked + 1))
        done
        while [ "$#" -ge 2 ]; do
          /bin/rm -f "$1"
          shift 2
        done
        """
}

/// Why installing or removing the command failed.
enum CommandLineToolError: Error, Equatable, LocalizedError {
    /// Something that isn't mdv's link is at the path.
    case occupied(CommandLineToolInstaller.Occupant)
    /// Nothing is installed at the path.
    case notInstalled
    /// The path changed while mdv was looking at it.
    case changed
    /// The folder needs an administrator to change.
    case needsAdministrator
    /// The reader cancelled the administrator password prompt.
    case cancelled
    case failed(String)

    init(errno code: Int32) {
        switch code {
        case EACCES, EPERM, EROFS:
            self = .needsAdministrator
        default:
            self = .failed(String(cString: strerror(code)))
        }
    }

    var errorDescription: String? {
        switch self {
        case .occupied(let occupant):
            switch occupant {
            case .file: "A file that isn’t mdv’s link is in the way."
            case .folder: "A folder is in the way."
            case .link(let destination): "A link to \(destination) is in the way."
            case .other: "Something that isn’t mdv’s link is in the way."
            }
        case .notInstalled: "The command line tool isn’t installed there."
        case .changed: "The file changed while mdv was installing. Try again."
        case .needsAdministrator: "Changing this folder needs an administrator."
        case .cancelled: "Cancelled."
        case .failed(let message): message
        }
    }
}
