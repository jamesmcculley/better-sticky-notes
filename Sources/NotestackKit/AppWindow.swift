import AppKit
import Carbon.HIToolbox

final class AppWindow: NSWindow {
    var onUndo: (() -> Void)?

    var onNavigate: ((Int) -> Void)?

    convenience init() {
        self.init(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false // SwiftUI draws its own shadow; a second native one would double up
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true // the whole note is the drag handle -- there's nothing else in the window
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "z", let onUndo {
            onUndo()
            return
        }
        if flags.isEmpty, let onNavigate {
            switch Int(event.keyCode) {
            case kVK_LeftArrow: onNavigate(-1); return
            case kVK_RightArrow: onNavigate(1); return
            default: break
            }
        }
        super.keyDown(with: event)
    }
}
