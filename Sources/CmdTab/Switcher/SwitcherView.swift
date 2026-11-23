import SwiftUI

enum SwitcherLayout {
    static let listWidth: CGFloat = 580
    static let previewWidth: CGFloat = 380
    static let appColumnWidth: CGFloat = 170
    static let searchHeight: CGFloat = 40
    static let minimumPreviewHeight: CGFloat = 260
    static let maximumScreenFraction: CGFloat = 0.7

    static func size(rows: Int, isSearching: Bool, showsPreview: Bool, screenHeight: CGFloat) -> CGSize {
        var height = CGFloat(max(rows, 1)) * Theme.rowHeight
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

    private var theme: Theme { model.theme }

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
                PreviewPane(row: model.selected, image: model.preview, theme: theme)
                    .frame(width: SwitcherLayout.previewWidth)
            }
        }
        .font(Theme.font)
        .background(theme.background)
    }

    private var searchField: some View {
        HStack(spacing: 2) {
            Text(model.query).foregroundStyle(theme.text)
            Rectangle().fill(theme.text).frame(width: 1, height: 16)
            Spacer()
        }
        .font(.system(size: 16))
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.searchHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.rows.isEmpty {
                        Text("No windows")
                            .foregroundStyle(theme.appName)
                            .frame(height: Theme.rowHeight)
                    }
                    ForEach(model.rows) { row in
                        RowView(row: row, isSelected: row.id == model.selectedID, typedHint: model.typedHint, theme: theme)
                            .id(row.id)
                            .onTapGesture { model.onPick?(row.id) }
                    }
                }
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
    let typedHint: String
    let theme: Theme

    private var isDimmed: Bool {
        row.window.isMinimized || row.window.isAppHidden
    }

    var body: some View {
        HStack(spacing: 9) {
            highlighted(row.window.appName, matches: row.appNameMatches, base: isSelected ? theme.selectedAppName : theme.appName)
                .frame(width: SwitcherLayout.appColumnWidth, alignment: .trailing)

            Group {
                if let icon = row.window.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 20, height: 20)

            highlighted(row.window.title, matches: row.titleMatches, base: theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !row.hint.isEmpty {
                hint
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(isDimmed ? 0.5 : 1)
        .padding(.horizontal, 12)
        .frame(height: Theme.rowHeight)
        .background(isSelected ? theme.selection : .clear)
        .contentShape(Rectangle())
    }

    private var hint: some View {
        let typedCount = row.hint.hasPrefix(typedHint) ? typedHint.count : 0
        let resting = isSelected ? theme.text.opacity(0.7) : theme.hint

        return (
            Text(row.hint.prefix(typedCount)).foregroundStyle(theme.text)
                + Text(row.hint.dropFirst(typedCount)).foregroundStyle(resting)
        )
        .font(.system(size: 12, weight: .medium, design: .rounded))
    }

    private func highlighted(_ string: String, matches: Set<Int>, base: Color) -> Text {
        guard !matches.isEmpty else {
            return Text(string).foregroundStyle(base)
        }

        return string.enumerated().reduce(Text("")) { text, character in
            let isMatch = matches.contains(character.offset)
            return text + Text(String(character.element))
                .foregroundStyle(isMatch ? theme.highlight : base)
                .fontWeight(isMatch ? .semibold : .regular)
        }
    }
}

private struct PreviewPane: View {
    let row: SwitcherRow?
    let image: NSImage?
    let theme: Theme

    var body: some View {
        ZStack {
            theme.previewBackground

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
            Rectangle().fill(theme.divider).frame(width: 1)
        }
    }
}
