import AppKit

// The first NSDocumentController created becomes `NSDocumentController.shared`, so create ours
// before anything asks for the shared one.
let documentController = DocumentController()
// AppKit app lifecycle without a main nib: set the delegate, then run. `NSApp.delegate` is weak;
// this top-level constant keeps the delegate alive for the life of the process.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
