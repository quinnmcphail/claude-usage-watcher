import AppKit

// Top-level code in main.swift runs in a nonisolated context, so build the app
// inside a @MainActor function before handing control to the run loop.
@MainActor
func runApp() -> Never {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    exit(0)
}

MainActor.assumeIsolated {
    runApp()
}
