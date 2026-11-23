import SwiftUI

enum SwitcherLayout {
    static let cornerRadius: CGFloat = 14
    static let listWidth: CGFloat = 600
    static let previewWidth: CGFloat = 380
    static let appColumnWidth: CGFloat = 170
    static let rowHeight: CGFloat = 30
    static let listPadding: CGFloat = 6
    static let searchHeight: CGFloat = 46
    static let minimumPreviewHeight: CGFloat = 260
    static let maximumScreenFraction: CGFloat = 0.7

    static func size(for model: SwitcherModel, showsPreview: Bool, screenHeight: CGFloat) -> CGSize {
        var height = CGFloat(max(model.rows.count, 1)) * rowHeight + listPadding * 2
        if model.isSearching {
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
                    SearchField(query: model.query, theme: theme)
                }
                list
            }
            .frame(width: SwitcherLayout.listWidth)

            if model.showsPreview {
                PreviewPane(row: model.selected, image: model.preview, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 13))
        .background(theme.background)
        .overlay {
            RoundedRectangle(cornerRadius: SwitcherLayout.cornerRadius).strokeBorder(theme.border)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.rows.isEmpty {
                        Text("No windows")
                            .foregroundStyle(theme.secondaryText)
                            .frame(height: SwitcherLayout.rowHeight)
                    }
                    ForEach(model.rows) { row in
                        RowView(row: row, isSelected: row.id == model.selectedID, typedHint: model.typedHint, theme: theme)
                            .id(row.id)
                            .onTapGesture { model.onPick?(row.id) }
                    }
                }
                .padding(SwitcherLayout.listPadding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) { _, id in
                proxy.scrollTo(id)
            }
        }
    }
}

private struct SearchField: View {
    let query: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            if query.isEmpty {
                Text("Search windows").foregroundStyle(theme.secondaryText)
            } else {
                Text(query).foregroundStyle(theme.text)
            }
            Spacer()
        }
        .font(.system(size: 18, weight: .light))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(height: SwitcherLayout.searchHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
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
        HStack(spacing: 10) {
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
                Keycap(hint: row.hint, typed: typedHint, isSelected: isSelected, theme: theme)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .opacity(isDimmed ? 0.5 : 1)
        .padding(.horizontal, 8)
        .frame(height: SwitcherLayout.rowHeight)
        .background(isSelected ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
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

private struct Keycap: View {
    let hint: String
    let typed: String
    let isSelected: Bool
    let theme: Theme

    var body: some View {
        let typedCount = hint.hasPrefix(typed) ? typed.count : 0
        let resting = isSelected ? theme.text.opacity(0.75) : theme.secondaryText

        return (
            Text(hint.prefix(typedCount)).foregroundStyle(theme.text)
                + Text(hint.dropFirst(typedCount)).foregroundStyle(resting)
        )
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .textCase(.uppercase)
        .padding(.horizontal, 5)
        .frame(minWidth: 20, minHeight: 18)
        .background(isSelected ? theme.text.opacity(0.18) : theme.keycap, in: RoundedRectangle(cornerRadius: 5))
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .padding(18)
            } else if let icon = row?.window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
        }
        .frame(width: SwitcherLayout.previewWidth)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.divider).frame(width: 1)
        }
    }
}
