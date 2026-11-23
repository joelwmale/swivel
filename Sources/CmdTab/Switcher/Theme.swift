import AppKit
import SwiftUI

/// Aura Dark, taken from the VS Code theme's workbench colours.
enum Theme {
    static let background = Color(hex: 0x15141b)
    static let previewBackground = Color(hex: 0x110f18)
    static let border = Color(hex: 0x2d2d2d)
    static let selection = Color(hex: 0x2e2b38)
    static let text = Color(hex: 0xedecee)
    static let muted = Color(hex: 0x6d6d6d)
    static let accent = Color(hex: 0xa277ff)
    static let highlight = Color(hex: 0xffca85)

    static let cornerRadius: CGFloat = 12
    static let rowHeight: CGFloat = 30
    static let fontSize: CGFloat = 13

    static func font(_ choice: SwitcherFont) -> Font {
        switch choice {
        case .system:
            return .system(size: fontSize)
        case .mono:
            let preferred = "IBM Plex Mono"
            if NSFontManager.shared.availableFontFamilies.contains(preferred) {
                return .custom(preferred, size: fontSize)
            }
            return .system(size: fontSize, design: .monospaced)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
