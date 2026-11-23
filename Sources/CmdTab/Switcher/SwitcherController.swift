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
        case KeyCode.q where command:
            perform(.quit)
        case KeyCode.w where command:
            perform(.close)
        case KeyCode.m where command:
            perform(.minimize)
        case KeyCode.h where command:
            perform(.hide)
        case KeyCode.delete where mode.isSearch:
            model.query = command ? "" : String(model.query.dropLast())
            applyQuery(resetSelection: true)
        default:
            guard mode.isSearch, !command else {
                return
            }
            let typed = Self.characters(from: event)
            if !typed.isEmpty {
                model.query += typed
                applyQuery(resetSelection: true)
            }
        }
    }

    private static func characters(from event: CGEvent) -> String {
        // The search hotkey's modifier may still be down for the first letters.
        guard let plain = event.copy() else {
            return ""
        }
        plain.flags = plain.flags.subtracting([.maskAlternate, .maskControl])

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
        model.font = Theme.font(Settings.font)
        model.selectedID = nil

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

        candidates = store.windows.filter { window in
            if case .sameApp(let pid) = mode, window.pid != pid || window.windowID == nil {
                return false
            }
            return (Settings.allSpaces || window.isOnCurrentSpace)
                && (Settings.showMinimized || !window.isMinimized)
                && (Settings.showHidden || !window.isAppHidden)
                && (Settings.showWindowlessApps || window.windowID != nil)
        }

        applyQuery(resetSelection: false)
    }

    private func applyQuery(resetSelection: Bool) {
        let previousIndex = model.selectedIndex ?? 0

        if model.query.isEmpty {
            model.rows = candidates.map { SwitcherRow(window: $0) }
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

    private func move(by offset: Int) {
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

        visibleScreens = Self.targetScreens()
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
            let size = SwitcherLayout.size(
                rows: model.rows.count,
                isSearching: model.isSearching,
                showsPreview: model.showsPreview,
                screenHeight: screen.visibleFrame.height
            )
            panel.place(on: screen, size: size, pinTop: model.isSearching)
        }
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
            let pointer = NSEvent.mouseLocation
            chosen = [screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? fallback]
        }
        return chosen.compactMap { $0 }
    }
}
