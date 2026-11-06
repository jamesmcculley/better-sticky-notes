import AppKit
import Carbon.HIToolbox

/// The app's one window (ADR 0022): a single sticky note, nothing else -- no sidebar, no other
/// panes, auto-sized to its content the same way every note window was before ADR 0018's
/// multi-pane detour. Borderless and floating (`level = .floating`), not resizable -- there's
/// nothing to resize into, the window is always exactly the size of the one note shown
/// (`AppController.render()` calls `setContentSize` after every update).
final class AppWindow: NSWindow {
    /// Undoes the single most recent item deletion (ADR 0011) -- a local `keyDown` override, not
    /// a global hotkey: it's only ever reached as the *last* stop in the responder chain, after
    /// whatever's focused (a text field with its own built-in Cocoa undo) has had first refusal.
    var onUndo: (() -> Void)?

    /// ←/→ move to the previous/next day's note (ADR 0023) -- same "last stop in the responder
    /// chain" reasoning as `onUndo`: a focused `TextField`'s cursor movement gets first refusal,
    /// so this only ever fires when nothing is actively being edited. `+1`/`-1`, same sign
    /// convention `ClickThroughHostingView.onNavigate` uses.
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
