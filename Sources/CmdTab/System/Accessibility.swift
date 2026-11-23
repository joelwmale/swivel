import AppKit
import ApplicationServices

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else {
            return nil
        }
        return value as? T
    }

    var windowID: CGWindowID {
        var id: CGWindowID = 0
        _AXUIElementGetWindow(self, &id)
        return id
    }

    var size: CGSize? {
        guard let value: AXValue = attribute(kAXSizeAttribute) else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    var isSwitchableWindow: Bool {
        guard let subrole: String = attribute(kAXSubroleAttribute) else {
            return false
        }
        return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
    }

    func perform(_ action: String) {
        AXUIElementPerformAction(self, action as CFString)
    }

    func set(_ name: String, to value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, name as CFString, value)
    }

    /// `kAXWindowsAttribute` only returns windows on the current Space. Windows
    /// elsewhere are still addressable by element id, so probe the id range.
    static func windowsOnAllSpaces(of pid: pid_t) -> [AXUIElement] {
        let probedElementIDs: Range<UInt64> = 0..<1000
        let cocoaSignature: Int32 = 0x636f_636f

        var token = Data()
        withUnsafeBytes(of: pid) { token.append(contentsOf: $0) }
        withUnsafeBytes(of: Int32(0)) { token.append(contentsOf: $0) }
        withUnsafeBytes(of: cocoaSignature) { token.append(contentsOf: $0) }
        let headerLength = token.count

        return probedElementIDs.compactMap { elementID in
            var candidate = token.prefix(headerLength)
            withUnsafeBytes(of: elementID) { candidate.append(contentsOf: $0) }

            guard let element = _AXUIElementCreateWithRemoteToken(candidate as CFData)?.takeRetainedValue(),
                  element.isSwitchableWindow
            else {
                return nil
            }
            return element
        }
    }
}

enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            open(pane: "Privacy_ScreenCapture")
        }
    }

    static func open(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
