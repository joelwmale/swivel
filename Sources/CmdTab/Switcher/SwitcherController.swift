import AppKit
import CmdTabCore

final class SwitcherController {
    private enum Mode {
        case allWindows
        case sameApp(pid_t)
        case search

        var isSearch: Bool {
            if case .search = self { return true }
            return false
        }
    }

    private enum RowAction {
        case quit, close, minimize, hide
    }

    /// A quick Cmd+Tab tap switches without the panel ever flashing up.
    private static let showDelay: TimeInterval = 0.1
    private static let refreshAfterActionDelay: TimeInterval = 0.35

    private let store = WindowStore.shared
    private let model = SwitcherModel()
    private var mode: Mode?
    private var candidates: [WindowInfo] = []
    private var panels: [SwitcherPanel] = []
    private var visibleScreens: [NSScreen] = []
    private var sessionScreens: [NSScreen] = []
    private var scopeBounds: CGRect?
    private var isPeeking = false
    private var pendingShow: DispatchWorkItem?
    private var clickMonitor: Any?

    init() {
        model.onPick = { [weak self] id in
            self?.model.selectedID = id
            self?.commit()
        }
    }

    // MARK: - Keyboard

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))

        guard let mode else {
            return type == .keyDown && beginIfHotkey(key: key, flags: flags)
        }

        switch type {
        case .flagsChanged:
            if !mode.isSearch, !flags.contains(.maskCommand) {
                commit()
            }
            return false
        case .keyDown:
            handleKeyDown(key: key, flags: flags, event: event, mode: mode)
            return true
        default:
            if key == KeyCode.space {
                setPeeking(false)
            }
            return true
        }
    }

    private func beginIfHotkey(key: Int, flags: CGEventFlags) -> Bool {
        let modifiers = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
        let backwards = flags.contains(.maskShift)

        if modifiers == .maskCommand, key == KeyCode.tab {
            begin(.allWindows, backwards: backwards)
            return true
        }
        if modifiers == .maskCommand, key == KeyCode.grave {
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                begin(.sameApp(pid), backwards: backwards)
            }
            return true
        }
        if let hotkey = Settings.searchHotkey.combo, modifiers == hotkey.modifiers, key == hotkey.key {
            begin(.search, backwards: false)
            return true
        }
        return false
    }

    private func handleKeyDown(key: Int, flags: CGEventFlags, event: CGEvent, mode: Mode) {
        let backwards = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)

        switch key {
        case KeyCode.escape:
            end()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            commit()
        case KeyCode.tab, KeyCode.grave:
            move(by: backwards ? -1 : 1)
        case KeyCode.down:
            move(by: 1)
        case KeyCode.up:
            move(by: -1)
        case KeyCode.q where command && backwards:
            perform(.quit)
        case KeyCode.w where command && backwards:
            perform(.close)
        case KeyCode.m where command && backwards:
            perform(.minimize)
        case KeyCode.h where command && backwards:
            perform(.hide)
        case KeyCode.space where !mode.isSearch:
            setPeeking(true)
        case KeyCode.delete where mode.isSearch:
            model.query = command ? "" : String(model.query.dropLast())
            applyQuery(resetSelection: true)
        default:
            let typed = Self.characters(from: event)
            guard !typed.isEmpty else {
                return
            }
            if !mode.isSearch {
                typeHint(typed.lowercased())
            } else if !command {
                model.query += typed
                applyQuery(resetSelection: true)
            }
        }
    }

    private static func characters(from event: CGEvent) -> String {
        // Command is held throughout a Cmd+Tab session, and the search hotkey's
        // modifier may still be down for the first letters.
        guard let plain = event.copy() else {
            return ""
        }
        plain.flags = plain.flags.subtracting([.maskCommand, .maskAlternate, .maskControl])

        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        plain.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)

        return String(utf16CodeUnits: buffer, count: length)
            .filter { $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f && !(0xf700...0xf8ff).contains($0.value) } }
    }

    // MARK: - Session

    private func begin(_ mode: Mode, backwards: Bool) {
        self.mode = mode
        model.isSearching = mode.isSearch
        model.query = ""
        model.preview = nil
        model.showsPreview = Settings.showPreview
        model.theme = Settings.theme.theme
        model.typedHint = ""
        model.selectedID = nil
        isPeeking = false
        sessionScreens = Self.targetScreens()
        scopeBounds = Settings.currentDisplayOnly ? Self.scopeBounds(for: sessionScreens) : nil

        reloadCandidates()

        guard !model.rows.isEmpty || mode.isSearch else {
            self.mode = nil
            return
        }

        let start = backwards ? model.rows.count - 1 : min(1, model.rows.count - 1)
        select(index: start)

        if mode.isSearch {
            show()
        } else {
            let work = DispatchWorkItem { [weak self] in self?.show() }
            pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
        }

        store.refresh { [weak self] in
            self?.reloadCandidates()
        }
    }

    private func commit() {
        let window = model.selected?.window
        end()

        if let window {
            store.touch(window.id)
            WindowActions.focus(window)
        }
    }

    private func end() {
        pendingShow?.cancel()
        pendingShow = nil
        mode = nil
        panels.forEach { $0.orderOut(nil) }
        visibleScreens = []

        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func perform(_ action: RowAction) {
        guard let window = model.selected?.window else {
            return
        }

        switch action {
        case .quit: WindowActions.quitApp(of: window)
        case .close: WindowActions.close(window)
        case .minimize: WindowActions.toggleMinimized(window)
        case .hide: WindowActions.toggleAppHidden(of: window)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshAfterActionDelay) { [weak self] in
            self?.store.refresh {
                self?.reloadCandidates()
            }
        }
    }

    // MARK: - Rows

    private func reloadCandidates() {
        guard let mode else {
            return
        }

        let excluded = Settings.excludedApps

        candidates = store.windows.filter { window in
            if case .sameApp(let pid) = mode, window.pid != pid || window.windowID == nil {
                return false
            }
            if let scopeBounds, let frame = window.frame, !scopeBounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return false
            }
            return !excluded.contains(window.appName)
                && (Settings.allSpaces || window.isOnCurrentSpace)
                && (Settings.showMinimized || !window.isMinimized)
                && (Settings.showHidden || !window.isAppHidden)
                && (Settings.showWindowlessApps || window.windowID != nil)
        }

        applyQuery(resetSelection: false)
    }

    private func applyQuery(resetSelection: Bool) {
        let previousIndex = model.selectedIndex ?? 0

        if model.query.isEmpty {
            let hints = hintsForCandidates()
            model.rows = candidates.map { SwitcherRow(window: $0, hint: hints[$0.appName] ?? "") }
        } else {
            model.rows = candidates
                .compactMap { window -> (SwitcherRow, Int)? in
                    guard let match = FuzzyMatcher.match(model.query, in: "\(window.appName) \(window.title)") else {
                        return nil
                    }
                    let titleOffset = window.appName.count + 1
                    let row = SwitcherRow(
                        window: window,
                        appNameMatches: Set(match.indices.filter { $0 < titleOffset }),
                        titleMatches: Set(match.indices.filter { $0 >= titleOffset }.map { $0 - titleOffset })
                    )
                    return (row, match.score)
                }
                .enumerated()
                .sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }
                .map(\.element.0)
        }

        if resetSelection {
            select(index: 0)
        } else if model.selectedIndex == nil {
            select(index: min(previousIndex, model.rows.count - 1))
        } else {
            layout()
        }
    }

    private func hintsForCandidates() -> [String: String] {
        guard Settings.keyHints, case .allWindows = mode else {
            return [:]
        }

        let known = Settings.hintAssignments
        let hints = KeyHints.assign(candidates.map(\.appName), existing: known)
        if hints != known {
            Settings.hintAssignments = hints
        }
        return hints
    }

    private func typeHint(_ key: String) {
        var visibleHints: [String] = []
        for hint in model.rows.map(\.hint) where !hint.isEmpty && !visibleHints.contains(hint) {
            visibleHints.append(hint)
        }

        let step = KeyHints.step(typed: model.typedHint, key: key, hints: visibleHints)
        model.typedHint = step.typed

        let appRows = model.rows.indices.filter { model.rows[$0].hint == step.hint }
        guard let first = appRows.first else {
            return
        }

        if step.cycles {
            let current = appRows.firstIndex(of: model.selectedIndex ?? -1) ?? -1
            select(index: appRows[(current + 1) % appRows.count])
        } else if first == 0, appRows.count > 1 {
            // Row 0 is the window already in front; asking for its app means the next one.
            select(index: appRows[1])
        } else {
            select(index: first)
        }
    }

    private func setPeeking(_ peeking: Bool) {
        guard peeking != isPeeking else {
            return
        }

        isPeeking = peeking
        model.showsPreview = peeking || Settings.showPreview
        select(index: model.selectedIndex ?? -1)
    }

    private func move(by offset: Int) {
        model.typedHint = ""
        guard !model.rows.isEmpty else {
            return
        }
        let count = model.rows.count
        select(index: ((model.selectedIndex ?? 0) + offset + count) % count)
    }

    private func select(index: Int) {
        guard model.rows.indices.contains(index) else {
            model.selectedID = nil
            model.preview = nil
            layout()
            return
        }

        let row = model.rows[index]
        model.selectedID = row.id
        layout()

        guard model.showsPreview, let windowID = row.window.windowID else {
            model.preview = nil
            return
        }

        Thumbnailer.capture(windowID) { [weak self] image in
            if self?.model.selectedID == row.id {
                self?.model.preview = image
            }
        }
    }

    // MARK: - Panels

    private func show() {
        guard mode != nil else {
            return
        }

        visibleScreens = sessionScreens
        while panels.count < visibleScreens.count {
            panels.append(SwitcherPanel(model: model))
        }

        layout()
        for (index, panel) in panels.enumerated() {
            if index < visibleScreens.count {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }

        if clickMonitor == nil {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.end()
            }
        }
    }

    private func layout() {
        for (panel, screen) in zip(panels, visibleScreens) {
            func size(showsPreview: Bool) -> CGSize {
                SwitcherLayout.size(
                    rows: model.rows.count,
                    isSearching: model.isSearching,
                    showsPreview: showsPreview,
                    screenHeight: screen.visibleFrame.height
                )
            }

            panel.place(
                on: screen,
                size: size(showsPreview: model.showsPreview),
                anchor: size(showsPreview: isPeeking ? Settings.showPreview : model.showsPreview),
                pinTop: model.isSearching
            )
        }
    }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    /// With the switcher on every screen there is no single "its display", so
    /// the pointer decides.
    private static func scopeBounds(for screens: [NSScreen]) -> CGRect? {
        let screen = screens.count == 1 ? screens.first : screenUnderPointer()
        let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return displayID.map(CGDisplayBounds)
    }

    private static func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        let fallback = NSScreen.main ?? screens.first

        let chosen: [NSScreen?]
        switch Settings.displayTarget {
        case .all:
            return screens
        case .primary:
            chosen = [screens.first]
        case .focused:
            chosen = [fallback]
        case .mouse:
            chosen = [screenUnderPointer() ?? fallback]
        }
        return chosen.compactMap { $0 }
    }
}
