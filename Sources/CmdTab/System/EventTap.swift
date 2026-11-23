import CoreGraphics
import Foundation

final class EventTap {
    /// Return true to swallow the event.
    var handler: ((CGEventType, CGEvent) -> Bool)?

    private var port: CFMachPort?

    func start() -> Bool {
        guard port == nil else {
            return true
        }

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }
            let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

            // macOS disables a tap whose callback was slow; without this the
            // switcher would silently stop responding.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = tap.port {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            return tap.handler?(type, event) == true ? nil : Unmanaged.passUnretained(event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
