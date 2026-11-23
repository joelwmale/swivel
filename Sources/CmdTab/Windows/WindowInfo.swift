import AppKit
import ApplicationServices

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

    static func id(forWindow windowID: CGWindowID) -> String { "w\(windowID)" }
    static func id(forApp pid: pid_t) -> String { "a\(pid)" }
}
