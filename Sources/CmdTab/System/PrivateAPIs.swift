import ApplicationServices
import CoreGraphics

// Undocumented WindowServer and Accessibility entry points. Public API cannot
// replace the system Cmd+Tab, focus one window of an app without raising the
// rest, or see windows on other Spaces.

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

enum SymbolicHotKey: Int32, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6
}

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
@discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ isEnabled: Bool) -> CGError

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ windowIDs: CFArray) -> CFArray

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray

@_silgen_name("CGSHWCaptureWindowList")
func CGSHWCaptureWindowList(
    _ cid: CGSConnectionID,
    _ windowList: UnsafePointer<CGWindowID>,
    _ count: UInt32,
    _ options: UInt32
) -> Unmanaged<CFArray>

@_silgen_name("_AXUIElementGetWindow")
@discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?

@_silgen_name("GetProcessForPID")
@discardableResult
func GetProcessForPID(_ pid: pid_t, _ psn: inout ProcessSerialNumber) -> OSStatus

@_silgen_name("_SLPSSetFrontProcessWithOptions")
@discardableResult
func _SLPSSetFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ windowID: CGWindowID, _ mode: UInt32) -> CGError

@_silgen_name("SLPSPostEventRecordTo")
@discardableResult
func SLPSPostEventRecordTo(_ psn: inout ProcessSerialNumber, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

enum NativeSwitcher {
    static func setEnabled(_ enabled: Bool) {
        for hotKey in SymbolicHotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, enabled)
        }
    }

    /// The disabled state outlives this process, so a crash would leave the
    /// machine with no Cmd+Tab at all.
    static func restoreOnAbnormalExit() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP] {
            signal(signalNumber) { received in
                NativeSwitcher.setEnabled(true)
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
