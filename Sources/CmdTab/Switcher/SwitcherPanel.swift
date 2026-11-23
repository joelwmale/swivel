import AppKit
import SwiftUI

/// Clicks must land on the first press: the panel never becomes key.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SwitcherPanel: NSPanel {
    init(model: SwitcherModel) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = ClickThroughHostingView(rootView: SwitcherView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place(on screen: NSScreen, size: CGSize, pinTop: Bool) {
        let area = screen.visibleFrame
        // Search results change the height on every keystroke; pinning the top
        // edge stops the query line jumping around.
        let top = pinTop
            ? area.maxY - area.height * (1 - SwitcherLayout.maximumScreenFraction) / 2
            : area.midY + size.height / 2

        setFrame(
            CGRect(x: area.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
            display: true
        )
    }
}
