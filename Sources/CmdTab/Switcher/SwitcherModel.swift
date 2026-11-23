import AppKit
import Observation
import SwiftUI

struct SwitcherRow: Identifiable {
    let window: WindowInfo
    var appNameMatches: Set<Int> = []
    var titleMatches: Set<Int> = []

    var id: String { window.id }
}

@Observable
final class SwitcherModel {
    var rows: [SwitcherRow] = []
    var selectedID: String?
    var query = ""
    var isSearching = false
    var showsPreview = true
    var preview: NSImage?
    var font: Font = .system(size: Theme.fontSize)

    @ObservationIgnored var onPick: ((String) -> Void)?

    var selectedIndex: Int? {
        rows.firstIndex { $0.id == selectedID }
    }

    var selected: SwitcherRow? {
        selectedIndex.map { rows[$0] }
    }
}
