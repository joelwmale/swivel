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
        blur.maskImage = Self.roundedMask(radius: SwitcherLayout.cornerRadius)

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
        invalidateShadow()
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

/// Owns one panel per screen the switcher is shown on.
final class SwitcherPresenter {
    var onClickOutside: (() -> Void)?

    private static let fadeInDuration: TimeInterval = 0.08

    private let model: SwitcherModel
    private var panels: [SwitcherPanel] = []
    private var screens: [NSScreen] = []
    private var clickMonitor: Any?

    init(model: SwitcherModel) {
        self.model = model
    }

    func show(on screens: [NSScreen]) {
        self.screens = screens
        while panels.count < screens.count {
            panels.append(SwitcherPanel(model: model))
        }

        layout()
        for panel in panels.prefix(screens.count) {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
            }
        }

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.onClickOutside?()
            }
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        screens = []

        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    func layout() {
        for (panel, screen) in zip(panels, screens) {
            let height = screen.visibleFrame.height
            panel.place(
                on: screen,
                size: SwitcherLayout.size(for: model, showsPreview: model.showsPreview, screenHeight: height),
                anchor: SwitcherLayout.size(for: model, showsPreview: model.pinsPreview, screenHeight: height),
                pinTop: model.isSearching
            )
        }
    }
}
