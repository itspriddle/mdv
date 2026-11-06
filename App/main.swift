import AppKit

// AppKit app lifecycle without a main nib: set the delegate, then run. `NSApp.delegate` is weak;
// this top-level constant keeps the delegate alive for the life of the process.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
