import Foundation

/// Why a privileged run failed.
enum PrivilegedRunError: Error, Equatable {
    /// The reader cancelled the password prompt.
    case cancelled
    /// The script exited with a non-zero status; `message` is what it wrote to stderr.
    case exitStatus(Int32, message: String)
    case failed(String)
}

/// Runs one of `CommandLineToolInstaller`'s fixed shell scripts with administrator rights.
///
/// `script` is always one of the installer's `static let` scripts and `arguments` are its
/// positional parameters (`$1`…); a runner passes them to `/bin/sh -c` as separate, quoted
/// words and never builds a command out of them. Tests use a runner that runs the same scripts
/// without privileges over temp folders.
protocol PrivilegedRunning: Sendable {
    func run(script: String, arguments: [String]) async throws(PrivilegedRunError)
}

/// The app's runner: AppleScript's `do shell script … with administrator privileges`, which asks
/// for an administrator's password (`AuthorizationExecuteWithPrivileges` is deprecated and a
/// privileged helper tool is too much for one link).
///
/// The AppleScript source is a constant. The script and its arguments are passed as Apple
/// event parameters to its `run_privileged` handler, which quotes each one with `quoted form
/// of`, so no value is ever spliced into AppleScript or shell source.
struct AppleScriptPrivilegedRunner: PrivilegedRunning {
    /// The handler. `do shell script` runs `command` with `/bin/sh -c`.
    static let source = """
        on run_privileged(scriptText, argumentList)
            set command to "/bin/sh -c " & quoted form of scriptText & " peep"
            repeat with argument in argumentList
                set command to command & " " & quoted form of (contents of argument)
            end repeat
            do shell script command with administrator privileges
        end run_privileged
        """

    /// The same handler without `with administrator privileges`, for tests of the quoting and
    /// the Apple event plumbing (no password prompt).
    static let unprivilegedSource = source.replacingOccurrences(of: " with administrator privileges", with: "")

    /// Whether to ask for an administrator's password: always, except in tests.
    let asAdministrator: Bool

    init(asAdministrator: Bool = true) {
        self.asAdministrator = asAdministrator
    }

    /// AppleScript's "user cancelled" error number.
    private static let userCancelled = -128

    func run(script: String, arguments: [String]) async throws(PrivilegedRunError) {
        // NSAppleScript belongs on the main thread. The password prompt is another process, so
        // this blocks the main thread like any app-modal alert until the reader answers.
        let source = asAdministrator ? Self.source : Self.unprivilegedSource
        let result = await MainActor.run { Self.runOnMain(source: source, script: script, arguments: arguments) }
        if let result {
            throw result
        }
    }

    @MainActor
    private static func runOnMain(source: String, script: String, arguments: [String]) -> PrivilegedRunError? {
        guard let appleScript = NSAppleScript(source: source) else {
            return .failed("The installer script couldn’t be loaded.")
        }
        let argumentList = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            argumentList.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: script), at: 1)
        parameters.insert(argumentList, at: 2)

        // kASAppleScriptSuite, kASSubroutineEvent; kAutoGenerateReturnID, kAnyTransactionID.
        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("ascr"), eventID: fourCharCode("psbr"),
            targetDescriptor: .currentProcess(), returnID: -1, transactionID: 0)
        // Handler names in a subroutine event are lowercase.
        event.setParam(NSAppleEventDescriptor(string: "run_privileged"), forKeyword: fourCharCode("snam"))
        event.setParam(parameters, forKeyword: fourCharCode("----"))

        var errorInfo: NSDictionary?
        appleScript.executeAppleEvent(event, error: &errorInfo)
        guard let errorInfo else {
            return nil
        }
        let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 1
        let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "The command failed."
        if number == userCancelled {
            return .cancelled
        }
        // `do shell script` reports a non-zero exit status as the error number.
        return number > 0 ? .exitStatus(Int32(clamping: number), message: message) : .failed(message)
    }

    private static func fourCharCode(_ code: String) -> FourCharCode {
        code.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
