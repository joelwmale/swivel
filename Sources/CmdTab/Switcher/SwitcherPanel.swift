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

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.maskImage = Self.roundedMask(radius: Theme.cornerRadius)

        let content = ClickThroughHostingView(rootView: SwitcherView(model: model))
        content.frame = blur.bounds
        content.autoresizingMask = [.width, .height]
        blur.addSubview(content)

        contentView = blur
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `anchor` is the size kept centred; a larger `size` grows right and down
    /// from it, so the list stays put when the preview opens.
    func place(on screen: NSScreen, size: CGSize, anchor: CGSize, pinTop: Bool) {
        let area = screen.visibleFrame
        // Search results change the height on every keystroke; pinning the top
        // edge stops the query line jumping around.
        let top = pinTop
            ? area.maxY - area.height * (1 - SwitcherLayout.maximumScreenFraction) / 2
            : area.midY + anchor.height / 2

        setFrame(
            CGRect(x: area.midX - anchor.width / 2, y: top - size.height, width: size.width, height: size.height),
            display: true
        )
    }

    /// A layer corner radius does not clip a behind-window blur; a stretchable
    /// mask image does.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
