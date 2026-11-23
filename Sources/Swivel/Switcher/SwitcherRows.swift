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

    static func rows(for candidates: [WindowInfo], hints: [String: String]) -> [SwitcherRow] {
        candidates.map { SwitcherRow(window: $0, hint: hints[$0.appName] ?? "") }
    }

    /// Best match first; equal scores keep their most-recently-used order.
    static func rows(for candidates: [WindowInfo], matching query: String) -> [SwitcherRow] {
        let scored = candidates.enumerated().compactMap { position, window -> (row: SwitcherRow, score: Int, position: Int)? in
            guard let match = FuzzyMatcher.match(query, in: "\(window.appName) \(window.title)") else {
                return nil
            }

            let titleStart = window.appName.count + 1
            let row = SwitcherRow(
                window: window,
                appNameMatches: Set(match.indices.filter { $0 < titleStart }),
                titleMatches: Set(match.indices.filter { $0 >= titleStart }.map { $0 - titleStart })
            )
            return (row, match.score, position)
        }

        return scored
            .sorted { ($0.score, $1.position) > ($1.score, $0.position) }
            .map(\.row)
    }
}
