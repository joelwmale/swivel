import AppKit
import SwivelCore

/// Runs one switching session at a time: from the hotkey that opens the
/// switcher to the key release, Return or Escape that ends it.
final class SwitcherController {
    private enum RowAction {
        case quit, close, minimize, hide
    }

    /// A quick Cmd+Tab tap switches without the panel ever flashing up.
    private static let showDelay: TimeInterval = 0.1
    private static let refreshAfterActionDelay: TimeInterval = 0.35

    private let store = WindowStore.shared
    private let model = SwitcherModel()
    private lazy var presenter = SwitcherPresenter(model: model)

    private var mode: SwitcherMode?
    private var candidates: [WindowInfo] = []
    private var screens: [NSScreen] = []
    private var displayBounds: CGRect?
    private var pendingShow: DispatchWorkItem?

    init() {
        model.onPick = { [weak self] id in
            self?.model.selectedID = id
            self?.commit()
        }
        presenter.onClickOutside = { [weak self] in
            self?.end()
        }
    }

    // MARK: - Keyboard

    /// Returns true to swallow the event.
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

    private func handleKeyDown(key: Int, flags: CGEventFlags, event: CGEvent, mode: SwitcherMode) {
        let shift = flags.contains(.maskShift)
        let command = flags.contains(.maskCommand)

        switch key {
        case KeyCode.escape:
            end()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            commit()
        case KeyCode.tab, KeyCode.grave:
            move(by: shift ? -1 : 1)
        case KeyCode.down:
            move(by: 1)
        case KeyCode.up:
            move(by: -1)
        case KeyCode.q where command && shift:
            perform(.quit)
        case KeyCode.w where command && shift:
            perform(.close)
        case KeyCode.m where command && shift:
            perform(.minimize)
        case KeyCode.h where command && shift:
            perform(.hide)
        case KeyCode.space where !mode.isSearch:
            setPeeking(true)
        case KeyCode.delete where mode.isSearch:
            model.query = command ? "" : String(model.query.dropLast())
            rebuildRows(resetSelection: true)
        default:
            let typed = Self.characters(from: event)
            guard !typed.isEmpty else {
                return
            }
            if !mode.isSearch {
                typeHint(typed.lowercased())
            } else if !command {
                model.query += typed
                rebuildRows(resetSelection: true)
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

        let functionKeys: ClosedRange<UInt32> = 0xf700...0xf8ff
        return String(utf16CodeUnits: buffer, count: length).filter { character in
            character.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f && !functionKeys.contains($0.value) }
        }
    }

    // MARK: - Session

    private func begin(_ mode: SwitcherMode, backwards: Bool) {
        self.mode = mode
        screens = Settings.displayTarget.screens
        displayBounds = Settings.currentDisplayOnly ? scopedDisplayBounds() : nil

        model.isSearching = mode.isSearch
        model.theme = Settings.theme.theme
        model.pinsPreview = Settings.showPreview
        model.isPeeking = false
        model.query = ""
        model.typedHint = ""
        model.preview = nil
        model.selectedID = nil

        reloadCandidates()

        guard !model.rows.isEmpty || mode.isSearch else {
            self.mode = nil
            return
        }

        select(index: backwards ? model.rows.count - 1 : min(1, model.rows.count - 1))

        if mode.isSearch {
            presenter.show(on: screens)
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.mode != nil else {
                    return
                }
                presenter.show(on: screens)
            }
            pendingShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
        }

        store.refresh { [weak self] in
            self?.reloadCandidates()
        }
        NotificationCenter.default.post(name: .switcherDidOpen, object: nil)
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
        presenter.hide()
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

    /// With the switcher on every screen there is no single "its display", so
    /// the pointer decides.
    private func scopedDisplayBounds() -> CGRect? {
        let screen = screens.count == 1 ? screens.first : NSScreen.underPointer
        return screen?.displayBounds
    }

    // MARK: - Rows

    private func reloadCandidates() {
        guard let mode else {
            return
        }

        candidates = SwitcherRows.candidates(in: store.windows, mode: mode, displayBounds: displayBounds)
        rebuildRows(resetSelection: false)
    }

    private func rebuildRows(resetSelection: Bool) {
        let previousIndex = model.selectedIndex ?? 0

        if !model.query.isEmpty {
            model.rows = SwitcherRows.rows(for: candidates, matching: model.query)
        } else if Settings.keyHints, case .allWindows = mode {
            model.rows = SwitcherRows.rows(for: candidates, hints: SwitcherRows.hints(for: candidates))
        } else {
            model.rows = SwitcherRows.rows(for: candidates, hints: [:])
        }

        if resetSelection {
            select(index: 0)
        } else if model.selectedIndex == nil {
            select(index: min(previousIndex, model.rows.count - 1))
        } else {
            presenter.layout()
        }
    }

    // MARK: - Selection

    private func move(by offset: Int) {
        model.typedHint = ""
        guard !model.rows.isEmpty else {
            return
        }
        let count = model.rows.count
        select(index: ((model.selectedIndex ?? 0) + offset + count) % count)
    }

    private func typeHint(_ key: String) {
        var visibleHints: [String] = []
        for hint in model.rows.map(\.hint) where !hint.isEmpty && !visibleHints.contains(hint) {
            visibleHints.append(hint)
        }

        let step = KeyHints.step(typed: model.typedHint, key: key, hints: visibleHints)
        model.typedHint = step.typed

        let appRows = model.rows.indices.filter { model.rows[$0].hint == step.hint }
        if let row = KeyHints.row(among: appRows, selected: model.selectedIndex, cycles: step.cycles) {
            select(index: row)
        }
    }

    private func select(index: Int) {
        let row = model.rows.indices.contains(index) ? model.rows[index] : nil
        model.selectedID = row?.id
        presenter.layout()
        loadPreview(for: row)
    }

    private func setPeeking(_ peeking: Bool) {
        guard peeking != model.isPeeking else {
            return
        }

        model.isPeeking = peeking
        presenter.layout()
        loadPreview(for: model.selected)
    }

    private func loadPreview(for row: SwitcherRow?) {
        guard model.showsPreview, let row, let windowID = row.window.windowID else {
            model.preview = nil
            return
        }

        Thumbnailer.capture(windowID) { [weak self] image in
            if self?.model.selectedID == row.id {
                self?.model.preview = image
            }
        }
    }
}
