import AppKit

enum DisplayTarget: String, CaseIterable, Identifiable {
    case mouse, focused, primary, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mouse: "Screen with the pointer"
        case .focused: "Screen with the focused window"
        case .primary: "Primary screen"
        case .all: "All screens"
        }
    }
}

enum SearchHotkey: String, CaseIterable, Identifiable {
    case optionTab, optionSpace, controlSpace, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionTab: "⌥ Tab"
        case .optionSpace: "⌥ Space"
        case .controlSpace: "⌃ Space"
        case .off: "Off"
        }
    }

    var combo: (key: Int, modifiers: CGEventFlags)? {
        switch self {
        case .optionTab: (KeyCode.tab, .maskAlternate)
        case .optionSpace: (KeyCode.space, .maskAlternate)
        case .controlSpace: (KeyCode.space, .maskControl)
        case .off: nil
        }
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case glass, aura

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: "Translucent"
        case .aura: "Aura Dark"
        }
    }

    var theme: Theme {
        switch self {
        case .glass: .glass
        case .aura: .aura
        }
    }
}

enum SettingKey {
    static let displayTarget = "displayTarget"
    static let searchHotkey = "searchHotkey"
    static let theme = "theme"
    static let keyHints = "keyHints"
    static let showPreview = "showPreview"
    static let allSpaces = "allSpaces"
    static let showMinimized = "showMinimized"
    static let showHidden = "showHidden"
    static let showWindowlessApps = "showWindowlessApps"
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingKey.displayTarget: DisplayTarget.mouse.rawValue,
            SettingKey.searchHotkey: SearchHotkey.optionTab.rawValue,
            SettingKey.theme: ThemeChoice.glass.rawValue,
            SettingKey.keyHints: true,
            SettingKey.showPreview: true,
            SettingKey.allSpaces: true,
            SettingKey.showMinimized: true,
            SettingKey.showHidden: true,
            SettingKey.showWindowlessApps: true,
        ])
    }

    static var displayTarget: DisplayTarget {
        DisplayTarget(rawValue: defaults.string(forKey: SettingKey.displayTarget) ?? "") ?? .mouse
    }

    static var searchHotkey: SearchHotkey {
        SearchHotkey(rawValue: defaults.string(forKey: SettingKey.searchHotkey) ?? "") ?? .optionTab
    }

    static var theme: ThemeChoice {
        ThemeChoice(rawValue: defaults.string(forKey: SettingKey.theme) ?? "") ?? .glass
    }

    static var keyHints: Bool { defaults.bool(forKey: SettingKey.keyHints) }

    static var showPreview: Bool { defaults.bool(forKey: SettingKey.showPreview) }
    static var allSpaces: Bool { defaults.bool(forKey: SettingKey.allSpaces) }
    static var showMinimized: Bool { defaults.bool(forKey: SettingKey.showMinimized) }
    static var showHidden: Bool { defaults.bool(forKey: SettingKey.showHidden) }
    static var showWindowlessApps: Bool { defaults.bool(forKey: SettingKey.showWindowlessApps) }
}

enum KeyCode {
    static let tab = 48
    static let grave = 50
    static let space = 49
    static let escape = 53
    static let returnKey = 36
    static let keypadEnter = 76
    static let delete = 51
    static let up = 126
    static let down = 125
    static let q = 12
    static let w = 13
    static let h = 4
    static let m = 46
}
