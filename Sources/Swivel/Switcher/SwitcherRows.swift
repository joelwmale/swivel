import SwivelCore
import Foundation

enum SwitcherRows {
    static func candidates(in windows: [WindowInfo], mode: SwitcherMode, displayBounds: CGRect?) -> [WindowInfo] {
        let excluded = Settings.excludedApps

        return windows.filter { window in
            if case .sameApp(let pid) = mode, window.pid != pid || window.windowID == nil {
                return false
            }
            if let displayBounds, let frame = window.frame,
               !displayBounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                return false
            }
            return !excluded.contains(window.appName)
                && (Settings.allSpaces || window.isOnCurrentSpace)
                && (Settings.showMinimized || !window.isMinimized)
                && (Settings.showHidden || !window.isAppHidden)
                && (Settings.showWindowlessApps || window.windowID != nil)
        }
    }

    /// Learns a hint for any app seen for the first time.
    static func hints(for candidates: [WindowInfo]) -> [String: String] {
        let known = Settings.hintAssignments
        let hints = KeyHints.assign(candidates.map(\.appName), existing: known)
        if hints != known {
            Settings.hintAssignments = hints
        }
        return hints
    }

    static func rows(for candidates: [WindowInfo], hints: [String: String], expanded: Set<String>) -> [SwitcherRow] {
        candidates.flatMap { window -> [SwitcherRow] in
            let isExpanded = expanded.contains(window.id) && !window.tabs.isEmpty
            let row = SwitcherRow(window: window, hint: hints[window.appName] ?? "", isExpanded: isExpanded)
            let tabs = window.tabs.enumerated().map { index, tab in
                SwitcherRow(window: window, tab: tab, tabIndex: index, isNested: true)
            }
            return [row] + (isExpanded ? tabs : [])
        }
    }

    /// Best match first; equal scores keep their most-recently-used order.
    /// Tabs are searched too, except the selected one, which its window's row
    /// already stands for.
    static func rows(for candidates: [WindowInfo], matching query: String) -> [SwitcherRow] {
        let searchable = candidates.flatMap { window -> [SwitcherRow] in
            let tabs = window.tabs.enumerated()
                .filter { !$0.element.isSelected }
                .map { SwitcherRow(window: window, tab: $0.element, tabIndex: $0.offset) }
            return [SwitcherRow(window: window)] + tabs
        }

        let scored = searchable.enumerated().compactMap { position, row -> (row: SwitcherRow, score: Int, position: Int)? in
            let appName = row.window.appName
            guard let match = FuzzyMatcher.match(query, in: "\(appName) \(row.title)") else {
                return nil
            }

            var row = row
            let titleStart = appName.count + 1
            row.appNameMatches = Set(match.indices.filter { $0 < titleStart })
            row.titleMatches = Set(match.indices.filter { $0 >= titleStart }.map { $0 - titleStart })
            return (row, match.score, position)
        }

        return scored
            .sorted { ($0.score, $1.position) > ($1.score, $0.position) }
            .map(\.row)
    }
}
