import Cocoa

// Setup the custom manual lifecycle for the background input method server
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
