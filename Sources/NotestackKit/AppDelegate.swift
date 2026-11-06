import AppKit
import Carbon.HIToolbox
import UserNotifications

/// Accessory app: no Dock icon, lives in the menu bar. Standalone and local (ADR 0002) -- no
/// network, no account, just Markdown files in ~/Documents/Notestack/. One floating window
/// showing exactly one note, today's daily note (ADR 0022) -- the menu bar's job is just
/// show/hide plus a couple of global actions; there's nothing else to navigate to anymore.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: AppController!
    private var statusItem: NSStatusItem!
    private var showHideHotKeyRef: EventHotKeyRef?

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        app = AppController(store: NotesStore())
        app.start()

        setUpStatusItem()
        registerHotKeys()
        requestNotificationAuthorizationIfBundled()
    }

    /// UNUserNotificationCenter.current() crashes outright (an uncaught NSException, not a Swift
    /// error -- `bundleProxyForCurrentProcess is nil`) when the process isn't a real .app bundle
    /// with its own CFBundleIdentifier, which `swift run`'s bare binary never has. Real daily use
    /// runs the packaged .app (scripts/bundle.sh) and gets notifications; `swift run` for local
    /// dev just skips them instead of crashing.
    private func requestNotificationAuthorizationIfBundled() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("notestack: not running as a bundled .app -- skipping notification permission (see scripts/bundle.sh)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Notestack")

        let menu = NSMenu()
        // Already works as a real global hotkey (registerHotKeys() below) -- the menu item's own
        // keyEquivalent doesn't make it work, it just surfaces the shortcut that already exists.
        let showHideItem = menu.addItem(withTitle: "Show/Hide", action: #selector(toggleVisibility), keyEquivalent: "f")
        showHideItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())

        menu.addItem(withTitle: "Reveal Notes Folder", action: #selector(revealNotesFolder), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleVisibility() {
        app.toggleVisibility()
    }

    @objc private func revealNotesFolder() {
        app.revealNotesFolder()
    }

    // MARK: - Global hotkey (Carbon, not NSEvent.addGlobalMonitor -- doesn't need Accessibility
    // permission, which a background-ish utility like this would rather not ask for)

    private func registerHotKeys() {
        registerHotKey(id: 1, signature: fourCharCode("NOTE"), keyCode: UInt32(kVK_ANSI_F), ref: &showHideHotKeyRef) {
            [weak self] in self?.toggleVisibility()
        }
    }

    private func registerHotKey(
        id: UInt32, signature: OSType, keyCode: UInt32, ref: inout EventHotKeyRef?, action: @escaping () -> Void
    ) {
        let box = Unmanaged.passRetained(HotKeyAction(action)).toOpaque()
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var handlerRef: EventHandlerRef?
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let box = Unmanaged<HotKeyAction>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { box.run() }
            return noErr
        }, 1, &eventType, box, &handlerRef)
        RegisterEventHotKey(keyCode, UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }
}

/// A thin box so each hotkey's own closure can be recovered inside the C callback above via
/// Unmanaged -- EventHandlerUPP doesn't have a Swift-closure-friendly signature.
private final class HotKeyAction {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

/// `signature` fields above are 4-character OSType codes; spelled as strings for readability,
/// converted here the same way the original single-hotkey version wrote `OSType(0x4e4f_5445)`.
private func fourCharCode(_ string: StaticString) -> OSType {
    var result: OSType = 0
    string.withUTF8Buffer { buffer in
        for byte in buffer { result = (result << 8) | OSType(byte) }
    }
    return result
}
