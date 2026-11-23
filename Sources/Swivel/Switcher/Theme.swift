import AppKit
import SwiftUI

struct Theme {
    /// Drawn over the panel's blur; an opaque colour hides it.
    let background: Color
    let previewBackground: Color
    let border: Color
    let divider: Color
    let selection: Color
    let text: Color
    let appName: Color
    let selectedAppName: Color
    let secondaryText: Color
    let keycap: Color
    let highlight: Color

    static let glass = Theme(
        background: .black.opacity(0.28),
        previewBackground: .black.opacity(0.18),
        border: .white.opacity(0.14),
        divider: .white.opacity(0.08),
        selection: Color(nsColor: .controlAccentColor),
        text: .white,
        appName: .white.opacity(0.7),
        selectedAppName: .white,
        secondaryText: .white.opacity(0.5),
        keycap: .white.opacity(0.12),
        highlight: Color(hex: 0xffd60a)
    )

    /// Taken from the Aura Dark VS Code theme's workbench colours.
    static let aura = Theme(
        background: Color(hex: 0x15141b),
        previewBackground: Color(hex: 0x110f18),
        border: Color(hex: 0x2d2d2d),
        divider: Color(hex: 0x2d2d2d),
        selection: Color(hex: 0x2e2b38),
        text: Color(hex: 0xedecee),
        appName: Color(hex: 0x6d6d6d),
        selectedAppName: Color(hex: 0xa277ff),
        secondaryText: Color(hex: 0x6d6d6d),
        keycap: Color(hex: 0xedecee).opacity(0.08),
        highlight: Color(hex: 0xffca85)
    )
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
