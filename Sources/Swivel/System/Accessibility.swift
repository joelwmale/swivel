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

    var position: CGPoint? {
        guard let value: AXValue = attribute(kAXPositionAttribute) else {
            return nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
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

    static let screenRecordingProbeFlag = "--probe-screen-recording"

    /// A running process keeps the Screen Recording answer it got at launch,
    /// so a new grant is only visible to a fresh copy of the app. Blocks.
    static func screenRecordingGrantedSinceLaunch() -> Bool {
        guard !hasScreenRecording, let executable = Bundle.main.executableURL else {
            return false
        }

        let probe = Process()
        probe.executableURL = executable
        probe.arguments = [screenRecordingProbeFlag]

        do {
            try probe.run()
        } catch {
            return false
        }
        probe.waitUntilExit()
        return probe.terminationStatus == 0
    }

    /// Quits first and reopens from a shell: two live copies would fight over
    /// the system switcher, and the one quitting would turn it back on.
    static func relaunch() {
        let reopen = Process()
        reopen.executableURL = URL(fileURLWithPath: "/bin/sh")
        reopen.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? reopen.run()
        NSApp.terminate(nil)
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
