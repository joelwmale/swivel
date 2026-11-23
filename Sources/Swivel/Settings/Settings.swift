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
    static let currentDisplayOnly = "currentDisplayOnly"
    static let excludedApps = "excludedApps"
    static let hintAssignments = "hintAssignments"
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            SettingKey.displayTarget: DisplayTarget.mouse.rawValue,
            SettingKey.searchHotkey: SearchHotkey.optionTab.rawValue,
            SettingKey.theme: ThemeChoice.glass.rawValue,
            SettingKey.keyHints: true,
            SettingKey.showPreview: false,
            SettingKey.allSpaces: true,
            SettingKey.showMinimized: true,
            SettingKey.showHidden: true,
            SettingKey.showWindowlessApps: false,
            SettingKey.currentDisplayOnly: false,
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
    static var currentDisplayOnly: Bool { defaults.bool(forKey: SettingKey.currentDisplayOnly) }

    static var excludedApps: Set<String> {
        ExcludedApps.decode(defaults.string(forKey: SettingKey.excludedApps) ?? "")
    }

    static var hintAssignments: [String: String] {
        get { defaults.dictionary(forKey: SettingKey.hintAssignments) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: SettingKey.hintAssignments) }
    }
}

/// Stored as one app name per line so SwiftUI's `@AppStorage` can bind to it.
enum ExcludedApps {
    static func decode(_ stored: String) -> Set<String> {
        Set(stored.split(separator: "\n").map(String.init))
    }

    static func encode(_ names: Set<String>) -> String {
        names.sorted().joined(separator: "\n")
    }
}
