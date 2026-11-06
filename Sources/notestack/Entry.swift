import AppKit
import NotestackKit

// No SwiftUI App/Scene lifecycle: that gives up exactly the low-level window control (borderless,
// floating, resizable, a custom ⌘Z key handler) this app is built around. SwiftUI is used only
// for view content (RootView), hosted in one plain AppKit window (AppWindow, ADR 0018). All the
// real logic lives in the NotestackKit library target (see Package.swift's comment for why) --
// this executable is just the entry point.
@main
enum Entry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
