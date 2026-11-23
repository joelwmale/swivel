import AppKit
import ApplicationServices
import CmdTabCore

/// Keeps a most-recently-used list of every switchable window. Accessibility
/// calls block on the target app, so they all run on `queue`; `windows` and the
/// MRU order are only touched on the main thread.
final class WindowStore {
    static let shared = WindowStore()

    private(set) var windows: [WindowInfo] = []

    private let queue = DispatchQueue(label: "cmdtab.windows", qos: .userInteractive)
    private var mru = MRUList<String>()
    private var pendingRefresh: DispatchWorkItem?

    // Confined to `queue`.
    private var observers: [pid_t: AXObserver] = [:]
    private var elementCache: [CGWindowID: AXUIElement] = [:]
    private var unswitchableWindowIDs: Set<CGWindowID> = []

    private static let messagingTimeout: Float = 0.3
    private static let minimumWindowSize = CGSize(width: 100, height: 50)
    private static let refreshDebounce: TimeInterval = 0.15

    private struct AppSnapshot {
        let pid: pid_t
        let name: String
        let icon: NSImage?
        let isHidden: Bool
    }

    func start() {
        mru.seed(Self.onScreenWindowIDs().map(WindowInfo.id(forWindow:)))

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.noteFocusChanged(in: app.processIdentifier)
        }
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefresh()
            }
        }

        refresh()
    }

    func touch(_ id: String) {
        mru.touch(id)
        windows = mru.sorted(windows, by: \.id)
    }

    func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshDebounce, execute: work)
    }

    func refresh(completion: (() -> Void)? = nil) {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map {
                AppSnapshot(
                    pid: $0.processIdentifier,
                    name: $0.localizedName ?? "",
                    icon: $0.icon,
                    isHidden: $0.isHidden
                )
            }

        queue.async { [self] in
            let found = collectWindows(for: apps)

            DispatchQueue.main.async { [self] in
                mru.prune(keeping: Set(found.map(\.id)))
                windows = mru.sorted(found, by: \.id)
                completion?()
            }
        }
    }

    // MARK: - Focus tracking

    private func noteFocusChanged(in pid: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return
        }

        queue.async { [self] in
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            let focused: AXUIElement? = app.attribute(kAXFocusedWindowAttribute)
            let windowID = focused?.windowID ?? 0
            let id = windowID == 0 ? WindowInfo.id(forApp: pid) : WindowInfo.id(forWindow: windowID)

            DispatchQueue.main.async { [self] in
                mru.touch(id)
                scheduleRefresh()
            }
        }
    }

    private func observe(_ pid: pid_t, app: AXUIElement) {
        guard observers[pid] == nil else {
            return
        }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, _ in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let focusMoved = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
                .contains(notification as String)

            DispatchQueue.main.async {
                if focusMoved {
                    WindowStore.shared.noteFocusChanged(in: pid)
                } else {
                    WindowStore.shared.scheduleRefresh()
                }
            }
        }

        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else {
            return
        }

        for notification in [
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ] {
            AXObserverAddNotification(observer, app, notification as CFString, nil)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    // MARK: - Enumeration (on `queue`)

    private func collectWindows(for apps: [AppSnapshot]) -> [WindowInfo] {
        let currentSpaces = Self.currentSpaceIDs()
        let candidates = Self.windowIDsByProcess()
        let liveWindowIDs = Set(candidates.values.joined())
        let livePIDs = Set(apps.map(\.pid))

        elementCache = elementCache.filter { liveWindowIDs.contains($0.key) }
        unswitchableWindowIDs.formIntersection(liveWindowIDs)
        for (pid, observer) in observers where !livePIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
        }

        var result: [WindowInfo] = []

        for app in apps {
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
            observe(app.pid, app: appElement)

            let elements = switchableElements(of: app.pid, app: appElement, candidates: candidates[app.pid] ?? [], currentSpaces: currentSpaces)

            let appWindows = elements.compactMap { windowID, element -> WindowInfo? in
                guard let size = element.size,
                      size.width >= Self.minimumWindowSize.width,
                      size.height >= Self.minimumWindowSize.height
                else {
                    return nil
                }

                let title: String = element.attribute(kAXTitleAttribute) ?? ""
                let isMinimized: Bool = element.attribute(kAXMinimizedAttribute) ?? false
                let spaces = Self.spaces(of: windowID)

                return WindowInfo(
                    id: WindowInfo.id(forWindow: windowID),
                    windowID: windowID,
                    pid: app.pid,
                    appName: app.name,
                    title: title.isEmpty ? app.name : WindowTitle.clean(title, appName: app.name),
                    icon: app.icon,
                    isMinimized: isMinimized,
                    isAppHidden: app.isHidden,
                    isOnCurrentSpace: spaces.isEmpty || !spaces.isDisjoint(with: currentSpaces),
                    element: element,
                    frame: element.position.map { CGRect(origin: $0, size: size) }
                )
            }

            if appWindows.isEmpty {
                result.append(WindowInfo(
                    id: WindowInfo.id(forApp: app.pid),
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
                ))
            }
            result.append(contentsOf: appWindows)
        }

        return result
    }

    private func switchableElements(
        of pid: pid_t,
        app: AXUIElement,
        candidates: [CGWindowID],
        currentSpaces: Set<CGSSpaceID>
    ) -> [(CGWindowID, AXUIElement)] {
        var elements: [CGWindowID: AXUIElement] = [:]
        var order: [CGWindowID] = []

        func add(_ element: AXUIElement) {
            let windowID = element.windowID
            guard windowID != 0, elements[windowID] == nil else {
                return
            }
            elements[windowID] = element
            order.append(windowID)
            elementCache[windowID] = element
        }

        let listed: [AXUIElement] = app.attribute(kAXWindowsAttribute) ?? []
        listed.filter(\.isSwitchableWindow).forEach(add)

        for windowID in candidates where elements[windowID] == nil {
            if let cached = elementCache[windowID], cached.isSwitchableWindow {
                add(cached)
            }
        }

        let unresolved = candidates.filter { windowID in
            elements[windowID] == nil
                && !unswitchableWindowIDs.contains(windowID)
                && Self.isOnAnotherSpace(windowID, currentSpaces: currentSpaces)
        }

        if !unresolved.isEmpty {
            AXUIElement.windowsOnAllSpaces(of: pid).forEach(add)
            unswitchableWindowIDs.formUnion(unresolved.filter { elements[$0] == nil })
        }

        return order.compactMap { windowID in elements[windowID].map { (windowID, $0) } }
    }

    // MARK: - WindowServer queries

    private static func windowDescriptions(_ options: CGWindowListOption) -> [[String: Any]] {
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

    private static func onScreenWindowIDs() -> [CGWindowID] {
        windowDescriptions([.optionOnScreenOnly, .excludeDesktopElements])
            .filter(isNormalWindow)
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    }

    private static func windowIDsByProcess() -> [pid_t: [CGWindowID]] {
        var byProcess: [pid_t: [CGWindowID]] = [:]

        for description in windowDescriptions([.excludeDesktopElements]) where isNormalWindow(description) {
            guard let pid = description[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = description[kCGWindowNumber as String] as? CGWindowID
            else {
                continue
            }
            byProcess[pid, default: []].append(windowID)
        }

        return byProcess
    }

    private static func spaces(of windowID: CGWindowID) -> Set<CGSSpaceID> {
        let allSpacesMask: Int32 = 7
        let spaces = CGSCopySpacesForWindows(CGSMainConnectionID(), allSpacesMask, [windowID] as CFArray)
        return Set((spaces as? [NSNumber] ?? []).map(\.uint64Value))
    }

    private static func isOnAnotherSpace(_ windowID: CGWindowID, currentSpaces: Set<CGSSpaceID>) -> Bool {
        let spaces = spaces(of: windowID)
        return !spaces.isEmpty && spaces.isDisjoint(with: currentSpaces)
    }

    private static func currentSpaceIDs() -> Set<CGSSpaceID> {
        let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []

        return Set(displays.compactMap { display in
            let current = display["Current Space"] as? [String: Any]
            return (current?["id64"] as? NSNumber)?.uint64Value
        })
    }
}
