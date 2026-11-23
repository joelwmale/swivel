import AppKit
import ApplicationServices
import SwivelCore

struct WindowInfo: Identifiable {
    /// `w<windowID>` for a window, `a<pid>` for an app with no windows.
    let id: String
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    let isMinimized: Bool
    let isAppHidden: Bool
    let isOnCurrentSpace: Bool
    let element: AXUIElement?
    /// Global coordinates with a top-left origin, as CoreGraphics reports displays.
    let frame: CGRect?

    static func id(forWindow windowID: CGWindowID) -> String { "w\(windowID)" }
    static func id(forApp pid: pid_t) -> String { "a\(pid)" }
}

extension WindowInfo {
    init(windowlessApp app: WindowStore.AppSnapshot) {
        self.init(
            id: Self.id(forApp: app.pid),
            windowID: nil,
            pid: app.pid,
            appName: app.name,
            title: app.name,
            icon: app.icon,
            isMinimized: false,
            isAppHidden: app.isHidden,
            isOnCurrentSpace: true,
            element: nil,
            frame: nil
        )
    }

    /// Nil for windows too small to be worth switching to, such as tool palettes.
    init?(app: WindowStore.AppSnapshot, windowID: CGWindowID, element: AXUIElement, currentSpaces: Set<CGSSpaceID>) {
        let minimum = WindowServer.minimumWindowSize
        guard let size = element.size, size.width >= minimum.width, size.height >= minimum.height else {
            return nil
        }

        let title: String = element.attribute(kAXTitleAttribute) ?? ""
        let spaces = WindowServer.spaces(of: windowID)

        self.init(
            id: Self.id(forWindow: windowID),
            windowID: windowID,
            pid: app.pid,
            appName: app.name,
            title: title.isEmpty ? app.name : WindowTitle.clean(title, appName: app.name),
            icon: app.icon,
            isMinimized: element.attribute(kAXMinimizedAttribute) ?? false,
            isAppHidden: app.isHidden,
            isOnCurrentSpace: spaces.isEmpty || !spaces.isDisjoint(with: currentSpaces),
            element: element,
            frame: element.position.map { CGRect(origin: $0, size: size) }
        )
    }
}
