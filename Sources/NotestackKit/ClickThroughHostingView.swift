import AppKit
import SwiftUI

/// A plain `NSHostingView` doesn't override `acceptsFirstMouse(for:)` (NSView's default is
/// `false`), and this app's windows are a menu-bar accessory's floating panels -- essentially
/// never the key/active window, since focus normally sits on whatever app the owner was using.
/// Without this override, the *first* click on a checkbox (or anywhere else in a note) after
/// switching away just activates/raises the window instead of reaching the SwiftUI Button --
/// Cocoa's inactive-window click-eating behavior, which exists at the content view's
/// `acceptsFirstMouse`, not the window's -- overriding it on `NoteWindow` itself wouldn't help,
/// since AppKit consults the hit-tested *view*, and that's always the hosting view, never the
/// window. Returning `true` here makes every click register immediately, active or not -- the
/// standard fix for exactly this class of floating-panel app.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Scroll past a threshold moves to the previous/next day (ADR 0023) -- set by
    /// `AppController.render()` each time. `+1` means "scrolled forward" (next day), `-1` means
    /// "scrolled backward" (previous day); the sign-to-direction mapping is picked once here,
    /// not re-derived at every call site.
    var onNavigate: ((Int) -> Void)?

    /// Accumulates `scrollingDelta` across an entire gesture, since one trackpad swipe generates
    /// many individual `scrollWheel` events, not one -- without this, a single swipe would fire
    /// several days' worth of navigation instead of one. Reset to zero both when a threshold
    /// fires (so the next day doesn't need the full gesture to repeat) and whenever a new gesture
    /// begins (`event.phase == .began`), so leftover momentum from an earlier light scroll never
    /// carries into an unrelated later one.
    private var accumulatedScroll: CGFloat = 0
    private let scrollThreshold: CGFloat = 70

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        guard let onNavigate else { return }
        if event.phase.contains(.began) { accumulatedScroll = 0 }
        // Either axis works -- a trackpad two-finger scroll can register on whichever direction
        // feels more natural to swipe, vertical or horizontal; this just takes whichever one the
        // person is actually moving.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        accumulatedScroll += delta
        if accumulatedScroll >= scrollThreshold {
            onNavigate(1)
            accumulatedScroll = 0
        } else if accumulatedScroll <= -scrollThreshold {
            onNavigate(-1)
            accumulatedScroll = 0
        }
    }
}
