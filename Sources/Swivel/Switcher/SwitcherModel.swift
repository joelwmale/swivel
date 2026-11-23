import AppKit
import Observation

enum SwitcherMode {
    case allWindows
    case sameApp(pid_t)
    case search

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }
}

struct SwitcherRow: Identifiable {
    let window: WindowInfo
    var appNameMatches: Set<Int> = []
    var titleMatches: Set<Int> = []
    var hint = ""
    var tab: WindowTab?
    var tabIndex = 0
    /// Shown indented under its window rather than as a row in its own right.
    var isNested = false
    var isExpanded = false

    var id: String {
        tab == nil ? window.id : "\(window.id)#\(tabIndex)"
    }

    var title: String {
        tab?.title ?? window.title
    }
}

@Observable
final class SwitcherModel {
    var rows: [SwitcherRow] = []
    var selectedID: String?
    var query = ""
    var typedHint = ""
    var isSearching = false
    var theme = Theme.glass
    var preview: NSImage?
    var pinsPreview = false
    var isPeeking = false

    @ObservationIgnored var onPick: ((String) -> Void)?

    var showsPreview: Bool {
        pinsPreview || isPeeking
    }

    var selectedIndex: Int? {
        rows.firstIndex { $0.id == selectedID }
    }

    var selected: SwitcherRow? {
        selectedIndex.map { rows[$0] }
    }
}
