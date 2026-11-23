import CoreGraphics
import Foundation

enum WindowServer {
    static let minimumWindowSize = CGSize(width: 100, height: 50)

    /// Front to back.
    static func onScreenWindowIDs() -> [CGWindowID] {
        descriptions([.optionOnScreenOnly, .excludeDesktopElements])
            .filter(isNormalWindow)
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    static func windowIDsByProcess() -> [pid_t: [CGWindowID]] {
        var byProcess: [pid_t: [CGWindowID]] = [:]

        for description in descriptions([.excludeDesktopElements]) where isNormalWindow(description) {
            guard let pid = description[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = description[kCGWindowNumber as String] as? CGWindowID
            else {
                continue
            }
            byProcess[pid, default: []].append(windowID)
        }

        return byProcess
    }

    static func spaces(of windowID: CGWindowID) -> Set<CGSSpaceID> {
        let allSpacesMask: Int32 = 7
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [windowID] as CFArray)
        return Set((spaces as? [NSNumber] ?? []).map(\.uint64Value))
    }

    static func isOnAnotherSpace(_ windowID: CGWindowID, currentSpaces: Set<CGSSpaceID>) -> Bool {
        let spaces = spaces(of: windowID)
        return !spaces.isEmpty && spaces.isDisjoint(with: currentSpaces)
    }

    /// One per display.
    static func currentSpaceIDs() -> Set<CGSSpaceID> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []

        return Set(displays.compactMap { display in
            let current = display["Current Space"] as? [String: Any]
            return (current?["id64"] as? NSNumber)?.uint64Value
        })
    }

    private static func descriptions(_ options: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func isNormalWindow(_ description: [String: Any]) -> Bool {
        let layer = description[kCGWindowLayer as String] as? Int ?? -1
        let alpha = description[kCGWindowAlpha as String] as? Double ?? 0
        let bounds = (description[kCGWindowBounds as String] as? [String: CGFloat]) ?? [:]

        return layer == 0
            && alpha > 0
            && bounds["Width", default: 0] >= minimumWindowSize.width
            && bounds["Height", default: 0] >= minimumWindowSize.height
    }
}
