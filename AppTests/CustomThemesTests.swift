import AppKit
import Foundation
import PeepCore
import Synchronization
import Testing

@testable import PeepApp

/// `ThemeFolderWatcher` against a real temporary folder: every way a theme file or the folder
/// itself changes is reported, and nothing else is.
@Suite("Theme folder watcher", .timeLimit(.minutes(1)))
struct ThemeFolderWatcherTests {
    /// Counts reports from the watcher's queue.
    final class Reports: Sendable {
        private let count = Mutex(0)

        func record() {
            count.withLock { $0 += 1 }
        }

        var value: Int { count.withLock { $0 } }

        /// Waits until at least `target` reports arrived (or `timeout` passed); returns the count.
        func wait(for target: Int, timeout: Duration = .seconds(3)) async throws -> Int {
            let deadline = ContinuousClock.now + timeout
            while value < target, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            return value
        }

        /// Waits `duration` and returns the count, to check that nothing more arrives.
        func settle(for duration: Duration = .milliseconds(400)) async throws -> Int {
            try await Task.sleep(for: duration)
            return value
        }
    }

    let root: URL
    let folder: URL
    let reports = Reports()

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "peep-theme-watcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        folder = root.appending(path: "peep/Themes", directoryHint: .isDirectory)
    }

    static let timing = ThemeFolderWatcher.Timing(latency: .milliseconds(30), maximumLatency: .milliseconds(100))

    func makeWatcher() -> ThemeFolderWatcher {
        let watcher = ThemeFolderWatcher(folder: folder, timing: Self.timing) { [reports] in reports.record() }
        watcher.start()
        return watcher
    }

    func makeFolder() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: folder.appending(path: name))
    }

    /// Runs `script` with `/bin/sh` in the themes folder, in a separate process.
    func shell(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "sh -c \(script)")
    }

    @Test("start reports once; a quiet folder reports nothing more")
    func initialReport() async throws {
        try makeFolder()
        let watcher = makeWatcher()
        defer { watcher.stop() }
        #expect(try await reports.wait(for: 1) == 1)
        #expect(try await reports.settle() == 1)
    }

    @Test("adding, editing in place, atomically replacing, renaming, and deleting a theme are each reported")
    func fileChanges() async throws {
        try makeFolder()
        let watcher = makeWatcher()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: root)
        }
        var expected = try await reports.wait(for: 1)

        try write("p {}", to: "a.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "added")
        expected = try await reports.settle()

        try shell("echo 'p { color: red }' >> a.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "edited in place")
        expected = try await reports.settle()

        try shell("printf 'p {}' > .a.tmp && mv .a.tmp a.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "atomic save")
        expected = try await reports.settle()

        // The replaced inode is watched: an in-place edit after the atomic save is seen.
        try shell("echo 'q {}' >> a.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "edited after atomic save")
        expected = try await reports.settle()

        try shell("mv a.css b.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "renamed")
        expected = try await reports.settle()

        try shell("rm b.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "deleted")
    }

    @Test("a burst of writes is one report")
    func debounce() async throws {
        try makeFolder()
        let watcher = makeWatcher()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let initial = try await reports.wait(for: 1)
        try shell("for i in 1 2 3 4 5 6 7 8 9 10; do echo \"p$i {}\" >> a.css; done")
        let after = try await reports.settle()
        #expect(after - initial >= 1)
        #expect(after - initial <= 2, "\(after - initial) reports for one burst")
    }

    @Test("a missing folder is noticed when created (several levels at once), deleted, and recreated")
    func folderLifecycle() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let watcher = makeWatcher()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: root)
        }
        var expected = try await reports.wait(for: 1)

        // peep/Themes and a file in one go: the root's source fires, then the deeper levels.
        try makeFolder()
        try write("p {}", to: "new.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "created")
        expected = try await reports.settle()
        // Now the folder is watched: an edit is seen.
        try shell("echo 'q {}' >> new.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "edit in the created folder")
        expected = try await reports.settle()

        try FileManager.default.removeItem(at: folder)
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "folder deleted")
        expected = try await reports.settle()

        try makeFolder()
        try write("p {}", to: "again.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "recreated")
        expected = try await reports.settle()
        try shell("echo 'q {}' >> again.css")
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "edit in the recreated folder")
    }

    @Test("a folder moved away is noticed, and so is one moved back")
    func folderMoved() async throws {
        try makeFolder()
        let watcher = makeWatcher()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: root)
        }
        var expected = try await reports.wait(for: 1)
        let away = root.appending(path: "elsewhere")
        try FileManager.default.moveItem(at: folder, to: away)
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "moved away")
        expected = try await reports.settle()
        try FileManager.default.moveItem(at: away, to: folder)
        expected += 1
        #expect(try await reports.wait(for: expected) >= expected, "moved back")
    }

    @Test("nothing is reported after stop")
    func stop() async throws {
        try makeFolder()
        let watcher = makeWatcher()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try await reports.wait(for: 1)
        watcher.stop()
        try write("p {}", to: "late.css")
        #expect(try await reports.settle() == initial)
    }
}

/// `CustomThemeLibrary` end to end: a temporary folder, private settings, and real windows.
@MainActor
@Suite("Custom themes", .serialized, .timeLimit(.minutes(1)))
final class CustomThemeLibraryTests: DocumentWindowTestCase {
    static let timing = ThemeFolderWatcher.Timing(latency: .milliseconds(30), maximumLatency: .milliseconds(100))

    var themesFolder: URL { folder.appending(path: "Themes", directoryHint: .isDirectory) }

    func write(_ css: String, to name: String) throws {
        try FileManager.default.createDirectory(at: themesFolder, withIntermediateDirectories: true)
        try Data(css.utf8).write(to: themesFolder.appending(path: name))
    }

    /// Waits until `condition` holds (or `timeout` passes), letting the main actor run.
    func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    func pageThemeCSS(in controller: DocumentWindowController) async throws -> String? {
        (try await controller.coordinator.webView.callAsyncJavaScript(
            "return document.getElementById('peep-theme').textContent;", arguments: [:], in: nil,
            contentWorld: AppScripts.world) as? String)?
            .trimmingCharacters(in: .newlines)
    }

    @Test("themes load at start, appear when added, update when edited, and go when deleted; open windows follow")
    func hotReload() async throws {
        defer { closeAll() }
        try write(
            "/* peep-theme\nname: Mine\nbackground: #102030\n*/\n.markdown-body { letter-spacing: 1px; }",
            to: "mine.css"
        )
        let settings = themeSettings()
        let library = CustomThemeLibrary(folder: themesFolder, settings: settings, timing: Self.timing)
        library.start()
        defer { library.stop() }

        #expect(try await waitUntil { settings.registry.contains(id: "custom:mine.css") }, "loaded at start")
        let (_, controller) = try await open(themeSettings: settings)
        controller.setTheme(id: "custom:mine.css")
        await controller.coordinator.pendingThemeSwap?.value
        #expect(controller.theme.displayName == "Mine")
        #expect(try await pageThemeCSS(in: controller)?.contains("letter-spacing: 1px") == true)

        // Edited: swapped in place in the open window.
        try write("/* peep-theme\nname: Mine\n*/\n.markdown-body { letter-spacing: 3px; }", to: "mine.css")
        #expect(
            try await waitUntil { controller.theme.stylesheet.contains("letter-spacing: 3px") },
            "edit reached the window")
        await controller.coordinator.pendingThemeSwap?.value
        #expect(try await pageThemeCSS(in: controller)?.contains("letter-spacing: 3px") == true)

        // Added: listed in the picker's custom section.
        try write("p {}", to: "second.css")
        #expect(try await waitUntil { settings.registry.contains(id: "custom:second.css") }, "added")
        let menu = ThemeMenu.makeMenu(settings: settings)
        menu.delegate?.menuNeedsUpdate?(menu)
        #expect(
            menu.items.compactMap { $0.representedObject as? String }.suffix(2) == [
                "custom:mine.css", "custom:second.css",
            ])

        // Broken: listed, disabled, with the reason. A theme that fails isn't registered, so the
        // window falls back to the default until the file is fixed.
        try write("@import 'x.css';", to: "mine.css")
        #expect(try await waitUntil { settings.customThemeFailures.map(\.fileName) == ["mine.css"] }, "failure listed")
        #expect(controller.theme == ThemeRegistry.bundled.defaultTheme)
        menu.delegate?.menuNeedsUpdate?(menu)
        let failure = try #require(menu.items.first { $0.title.hasPrefix("mine:") })
        #expect(failure.title == "mine: @import isn’t allowed (line 1)")
        #expect(failure.action == nil)
        #expect(!failure.isEnabled)

        // Fixed: the window shows it again (it kept its pick).
        try write(".markdown-body { letter-spacing: 5px; }", to: "mine.css")
        #expect(
            try await waitUntil { controller.theme.stylesheet.contains("letter-spacing: 5px") }, "fixed theme came back"
        )
        #expect(settings.customThemeFailures.isEmpty, "\(settings.customThemeFailures.map(\.message))")

        // Deleted: falls back to the default.
        try FileManager.default.removeItem(at: themesFolder.appending(path: "mine.css"))
        #expect(try await waitUntil { !settings.registry.contains(id: "custom:mine.css") }, "deleted")
        #expect(controller.theme == ThemeRegistry.bundled.defaultTheme)
        await controller.coordinator.pendingThemeSwap?.value
        #expect(
            try await pageThemeCSS(in: controller)
                == ThemeRegistry.bundled.defaultTheme.layerCSS.trimmingCharacters(in: .newlines))
        #expect(controller.themeID == "custom:mine.css", "the window remembers its pick")
    }

    @Test("Open Themes Folder creates a missing folder, and themes put in it load")
    func openFolderCreates() async throws {
        let settings = themeSettings()
        let nested = folder.appending(path: "Support/peep/Themes", directoryHint: .isDirectory)
        let library = CustomThemeLibrary(folder: nested, settings: settings, timing: Self.timing)
        library.start()
        defer { library.stop() }
        library.openFolder()
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: nested.path(percentEncoded: false), isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        try Data("p {}".utf8).write(to: nested.appending(path: "late.css"))
        #expect(try await waitUntil { settings.registry.contains(id: "custom:late.css") })
    }

    @Test("apply posts only when something changed")
    func applyPosts() {
        let settings = themeSettings()
        var posts = 0
        let token = NotificationCenter.default.addObserver(
            forName: ThemeSettings.didChangeNotification, object: settings, queue: nil
        ) { _ in posts += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        settings.apply(.empty)
        #expect(posts == 0)
        let failure = CustomThemeFailure(fileName: "x.css", problem: .notUTF8)
        settings.apply(CustomThemeCatalog(failures: [failure]))
        #expect(posts == 1)
        settings.apply(CustomThemeCatalog(failures: [failure]))
        #expect(posts == 1)
        let theme = Theme(id: "custom:a.css", displayName: "A", background: Theme.github.background, stylesheet: "")
        settings.apply(CustomThemeCatalog(themes: [theme], failures: [failure]))
        #expect(posts == 2)
        #expect(settings.registry == ThemeRegistry.bundled.adding([theme]))
    }

    @Test("a new window keeps a default custom theme that isn't loaded yet, and shows it once it is")
    func defaultBeforeLoad() async throws {
        defer { closeAll() }
        let settings = themeSettings()
        settings.defaultThemeID = "custom:later.css"
        let (_, controller) = try await open(themeSettings: settings)
        #expect(controller.themeID == "custom:later.css")
        #expect(controller.theme == ThemeRegistry.bundled.defaultTheme)
        let theme = Theme(
            id: "custom:later.css", displayName: "Later", background: Theme.serif.background, stylesheet: "")
        settings.apply(CustomThemeCatalog(themes: [theme]))
        #expect(controller.theme == theme)
    }

    @Test("failures are listed in the custom section, disabled; Open Themes Folder ends View > Theme")
    func menuItems() {
        let settings = themeSettings()
        settings.apply(
            CustomThemeCatalog(failures: [
                CustomThemeFailure(fileName: "big.css", problem: .tooLarge(bytes: 1_000_000, limit: 524_288))
            ]))
        let menu = ThemeMenu.makeMenu(settings: settings, includesFolderItem: true)
        menu.delegate?.menuNeedsUpdate?(menu)
        let titles = menu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(
            titles == [
                "GitHub", "Document", "Serif", "-", "big: Too large (977 KB; the limit is 512 KB)", "-",
                "Open Themes Folder",
            ])
        #expect(menu.items.last?.action == #selector(AppDelegate.openThemesFolder(_:)))
        // Without the folder item, the failure is last.
        let plainMenu = ThemeMenu.makeMenu(settings: settings)
        #expect(plainMenu.items.last?.title.hasPrefix("big:") == true)
    }
}
