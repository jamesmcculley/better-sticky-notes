import AppKit
import SwiftUI

final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onNavigate: ((Int) -> Void)?

    private var accumulatedScroll: CGFloat = 0
    private let scrollThreshold: CGFloat = 70

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        guard let onNavigate else { return }
        if event.phase.contains(.began) { accumulatedScroll = 0 }
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
