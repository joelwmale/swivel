import AppKit
import ApplicationServices
import SwivelCore

/// Keeps a most-recently-used list of every switchable window. Accessibility
/// calls block on the target app, so they all run on `queue`; `windows` and the
/// MRU order are only touched on the main thread.
final class WindowStore {
    static let shared = WindowStore()

    private(set) var windows: [WindowInfo] = []

    private let queue = DispatchQueue(label: "swivel.windows", qos: .userInteractive)
    private var mru = MRUList<String>()
    private var pendingRefresh: DispatchWorkItem?

    // Confined to `queue`.
    private var observers: [pid_t: AXObserver] = [:]
    private var elementCache: [CGWindowID: AXUIElement] = [:]
    private var unswitchableWindowIDs: Set<CGWindowID> = []

    private static let messagingTimeout: Float = 0.3
    private static let refreshDebounce: TimeInterval = 0.15

    struct AppSnapshot {
        let pid: pid_t
        let name: String
        let icon: NSImage?
        let isHidden: Bool
    }

    func start() {
        mru.seed(WindowServer.onScreenWindowIDs().map(WindowInfo.id(forWindow:)))

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
        let currentSpaces = WindowServer.currentSpaceIDs()
        let candidates = WindowServer.windowIDsByProcess()
        let liveWindowIDs = Set(candidates.values.joined())
        let livePIDs = Set(apps.map(\.pid))

        elementCache = elementCache.filter { liveWindowIDs.contains($0.key) }
        unswitchableWindowIDs.formIntersection(liveWindowIDs)
        for (pid, observer) in observers where !livePIDs.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
        }

        return apps.flatMap { app -> [WindowInfo] in
            let appElement = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
            observe(app.pid, app: appElement)

            let windows = switchableElements(
                of: app.pid,
                app: appElement,
                candidates: candidates[app.pid] ?? [],
                currentSpaces: currentSpaces
            ).compactMap { windowID, element in
                WindowInfo(app: app, windowID: windowID, element: element, currentSpaces: currentSpaces)
            }

            return windows.isEmpty ? [WindowInfo(windowlessApp: app)] : windows
        }
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
                && WindowServer.isOnAnotherSpace(windowID, currentSpaces: currentSpaces)
        }

        if !unresolved.isEmpty {
            AXUIElement.windowsOnAllSpaces(of: pid).forEach(add)
            unswitchableWindowIDs.formUnion(unresolved.filter { elements[$0] == nil })
        }

        return order.compactMap { windowID in elements[windowID].map { (windowID, $0) } }
    }
}
