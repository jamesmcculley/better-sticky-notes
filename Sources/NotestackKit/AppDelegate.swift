import AppKit
import Carbon.HIToolbox
import UserNotifications

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

    private func requestNotificationAuthorizationIfBundled() {
        guard Bundle.main.bundleIdentifier != nil else {
            print("notestack: not running as a bundled .app -- skipping notification permission (see scripts/bundle.sh)")
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }


    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Notestack")

        let menu = NSMenu()
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

private final class HotKeyAction {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
}

private func fourCharCode(_ string: StaticString) -> OSType {
    var result: OSType = 0
    string.withUTF8Buffer { buffer in
        for byte in buffer { result = (result << 8) | OSType(byte) }
    }
    return result
}
