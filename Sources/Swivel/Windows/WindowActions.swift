import AppKit
import ApplicationServices

enum WindowActions {
    private static let queue = DispatchQueue(label: "swivel.actions", qos: .userInteractive)

    static func focus(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)

        guard let windowID = window.windowID, let element = window.element else {
            app?.unhide()
            app?.activate()
            return
        }

        if window.isAppHidden {
            app?.unhide()
        }

        queue.async {
            if window.isMinimized {
                element.set(kAXMinimizedAttribute, to: kCFBooleanFalse)
            }

            var psn = ProcessSerialNumber()
            GetProcessForPID(window.pid, &psn)

            let userGenerated: UInt32 = 0x200
            _SLPSSetFrontProcessWithOptions(&psn, windowID, userGenerated)
            makeKeyWindow(windowID, psn: &psn)
            element.perform(kAXRaiseAction)
        }
    }

    static func close(_ window: WindowInfo) {
        queue.async {
            let button: AXUIElement? = window.element?.attribute(kAXCloseButtonAttribute)
            button?.perform(kAXPressAction)
        }
    }

    static func toggleMinimized(_ window: WindowInfo) {
        queue.async {
            window.element?.set(kAXMinimizedAttribute, to: window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue)
        }
    }

    static func quitApp(of window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.terminate()
    }

    static func toggleAppHidden(of window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        if window.isAppHidden {
            app?.unhide()
        } else {
            app?.hide()
        }
    }

    /// Bringing a process forward focuses whichever window it had last. These
    /// synthetic WindowServer event records move key status to `windowID`
    /// instead; the layout is undocumented and widely reverse-engineered.
    private static func makeKeyWindow(_ windowID: CGWindowID, psn: inout ProcessSerialNumber) {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { raw in
            bytes.replaceSubrange(0x3c..<0x40, with: raw)
        }
        bytes.replaceSubrange(0x20..<0x30, with: [UInt8](repeating: 0xff, count: 0x10))

        bytes[0x08] = 0x01
        SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        SLPSPostEventRecordTo(&psn, &bytes)
    }
}

enum Thumbnailer {
    private static let queue = DispatchQueue(label: "swivel.thumbnails", qos: .userInitiated)

    static func capture(_ windowID: CGWindowID, completion: @escaping (NSImage?) -> Void) {
        guard Permissions.hasScreenRecording else {
            completion(nil)
            return
        }

        queue.async {
            let ignoreGlobalClipShape: UInt32 = 1 << 11
            let nominalResolution: UInt32 = 1 << 9

            var id = windowID
            let captured = CGSHWCaptureWindowList(CGSMainConnectionID(), &id, 1, ignoreGlobalClipShape | nominalResolution)
                .takeRetainedValue() as? [CGImage]
            let image = captured?.first.map { NSImage(cgImage: $0, size: .zero) }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
