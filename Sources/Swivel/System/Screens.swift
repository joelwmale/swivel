import AppKit

extension NSScreen {
    static var underPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    /// In the top-left-origin coordinates Accessibility reports window frames in.
    var displayBounds: CGRect? {
        let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return displayID.map(CGDisplayBounds)
    }
}

extension DisplayTarget {
    var screens: [NSScreen] {
        let focused = NSScreen.main ?? NSScreen.screens.first

        let screen: NSScreen? = switch self {
        case .all: nil
        case .primary: NSScreen.screens.first
        case .focused: focused
        case .mouse: NSScreen.underPointer ?? focused
        }

        return self == .all ? NSScreen.screens : [screen].compactMap { $0 }
    }
}
