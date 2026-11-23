import SwiftUI

enum SwitcherLayout {
    static let listWidth: CGFloat = 520
    static let previewWidth: CGFloat = 380
    static let appColumnWidth: CGFloat = 140
    static let searchHeight: CGFloat = 40
    static let verticalPadding: CGFloat = 6
    static let minimumPreviewHeight: CGFloat = 260
    static let maximumScreenFraction: CGFloat = 0.7

    static func size(rows: Int, isSearching: Bool, showsPreview: Bool, screenHeight: CGFloat) -> CGSize {
        var height = CGFloat(max(rows, 1)) * Theme.rowHeight + verticalPadding * 2
        if isSearching {
            height += searchHeight
        }
        if showsPreview {
            height = max(height, minimumPreviewHeight)
        }

        return CGSize(
            width: listWidth + (showsPreview ? previewWidth : 0),
            height: min(height, screenHeight * maximumScreenFraction)
        )
    }
}

struct SwitcherView: View {
    let model: SwitcherModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.isSearching {
                    searchField
                }
                list
            }
            .frame(width: SwitcherLayout.listWidth)

            if model.showsPreview {
                PreviewPane(row: model.selected, image: model.preview)
                    .frame(width: SwitcherLayout.previewWidth)
            }
        }
        .font(model.font)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Text("›").foregroundStyle(Theme.accent)
            Text(model.query).foregroundStyle(Theme.text)
            Rectangle().fill(Theme.accent).frame(width: 1.5, height: 16)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.searchHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.rows.isEmpty {
                        Text("No windows")
                            .foregroundStyle(Theme.muted)
                            .frame(height: Theme.rowHeight)
                    }
                    ForEach(model.rows) { row in
                        RowView(row: row, isSelected: row.id == model.selectedID)
                            .id(row.id)
                            .onTapGesture { model.onPick?(row.id) }
                    }
                }
                .padding(.vertical, SwitcherLayout.verticalPadding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, id in
                proxy.scrollTo(id)
            }
        }
    }
}

private struct RowView: View {
    let row: SwitcherRow
    let isSelected: Bool

    private var isDimmed: Bool {
        row.window.isMinimized || row.window.isAppHidden
    }

    var body: some View {
        HStack(spacing: 10) {
            highlighted(row.window.appName, matches: row.appNameMatches, base: isSelected ? Theme.accent : Theme.muted)
                .frame(width: SwitcherLayout.appColumnWidth, alignment: .trailing)

            Group {
                if let icon = row.window.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 18, height: 18)

            highlighted(row.window.title, matches: row.titleMatches, base: Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(isDimmed ? 0.45 : 1)
        .padding(.horizontal, 12)
        .frame(height: Theme.rowHeight)
        .background(isSelected ? Theme.selection : .clear)
        .contentShape(Rectangle())
    }

    private func highlighted(_ string: String, matches: Set<Int>, base: Color) -> Text {
        guard !matches.isEmpty else {
            return Text(string).foregroundStyle(base)
        }

        return string.enumerated().reduce(Text("")) { text, character in
            text + Text(String(character.element))
                .foregroundStyle(matches.contains(character.offset) ? Theme.highlight : base)
        }
    }
}

private struct PreviewPane: View {
    let row: SwitcherRow?
    let image: NSImage?

    var body: some View {
        ZStack {
            Theme.previewBackground

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(16)
            } else if let icon = row?.window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.border).frame(width: 1)
        }
    }
}
