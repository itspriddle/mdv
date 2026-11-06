import Foundation
import JavaScriptCore
import Synchronization

/// Highlights code with the vendored highlight.js (`HighlightJSSource`) running in an
/// in-process JavaScriptCore context, so highlighting happens at render time and the output is
/// static `<span class="hljs-…">` markup (no JavaScript in the viewer or in `mdv --html`).
///
/// The `JSContext` is created and the scripts are evaluated on first use, then reused. Access
/// is serialized with a mutex because a `JSContext` isn't safe to use from several threads at
/// once. Code and language names are passed to JavaScript as values, never spliced into script
/// source. If the scripts fail to load, every call returns `nil` (plain code blocks).
///
/// The language must be one highlight.js knows (a name or alias, case-insensitive); there is no
/// auto-detection, matching GitHub.
public final class HighlightJSHighlighter: SyntaxHighlighter {
    /// A process-wide instance, so the context is loaded at most once.
    public static let shared = HighlightJSHighlighter()

    /// The vendored highlight.js version.
    public static let version = HighlightJSSource.version

    private let state = Mutex(State.unloaded)

    public init() {}

    public func highlight(_ code: String, language: String) -> String? {
        guard Self.isPlausibleLanguageName(language) else {
            return nil
        }
        return state.withLock { state -> String? in
            if case .unloaded = state {
                state = Self.load().map(State.loaded) ?? .failed
            }
            guard case .loaded(let engine) = state else {
                return nil
            }
            return engine.highlight(code, language: language)
        }
    }

    /// Loads the context eagerly (e.g. off the main thread at launch) so the first document
    /// doesn't pay for it. Returns whether highlight.js is usable.
    @discardableResult
    public func prepare() -> Bool {
        state.withLock { state -> Bool in
            if case .unloaded = state {
                state = Self.load().map(State.loaded) ?? .failed
            }
            if case .loaded = state {
                return true
            }
            return false
        }
    }

    /// Language names are short identifiers like `swift`, `c++`, `objective-c`, or `f#`;
    /// anything else can't be a highlight.js language and isn't worth a round trip.
    static func isPlausibleLanguageName(_ name: String) -> Bool {
        let bytes = name.utf8
        guard (1...32).contains(bytes.count) else {
            return false
        }
        return bytes.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                UInt8(ascii: "0")...UInt8(ascii: "9"):
                true
            default:
                "+#._-".utf8.contains(byte)
            }
        }
    }

    private enum State {
        case unloaded
        case loaded(Engine)
        case failed
    }

    private static func load() -> Engine? {
        guard let context = JSContext() else {
            return nil
        }
        context.name = "mdv highlight.js \(HighlightJSSource.version)"
        // Exceptions are reported through `context.exception`; don't log them.
        context.exceptionHandler = { context, exception in
            context?.exception = exception
        }
        // highlight.js may warn through `console`, which JavaScriptCore doesn't provide.
        context.evaluateScript("var console = { log() {}, warn() {}, error() {}, info() {}, debug() {} };")
        for script in HighlightJSSource.scripts {
            context.evaluateScript(script.source, withSourceURL: URL(string: "mdv-hljs:///\(script.name)"))
            if context.exception != nil {
                return nil
            }
        }
        let function = context.evaluateScript(
            """
            (function (code, language) {
              if (!hljs.getLanguage(language)) { return null; }
              return hljs.highlight(code, { language: language, ignoreIllegals: true }).value;
            })
            """
        )
        guard context.exception == nil, let function, function.isObject else {
            return nil
        }
        return Engine(context: context, function: function)
    }

    /// The loaded context. Only used while holding the mutex.
    private struct Engine {
        let context: JSContext
        let function: JSValue

        func highlight(_ code: String, language: String) -> String? {
            context.exception = nil
            let result = function.call(withArguments: [code, language])
            guard context.exception == nil, let result, result.isString else {
                context.exception = nil
                return nil
            }
            return result.toString()
        }
    }
}
