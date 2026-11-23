import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingKey.displayTarget) private var displayTarget = DisplayTarget.mouse
    @AppStorage(SettingKey.searchHotkey) private var searchHotkey = SearchHotkey.optionTab
    @AppStorage(SettingKey.theme) private var theme = ThemeChoice.glass
    @AppStorage(SettingKey.keyHints) private var keyHints = true
    @AppStorage(SettingKey.showPreview) private var showPreview = false
    @AppStorage(SettingKey.allSpaces) private var allSpaces = true
    @AppStorage(SettingKey.showMinimized) private var showMinimized = true
    @AppStorage(SettingKey.showHidden) private var showHidden = true
    @AppStorage(SettingKey.showWindowlessApps) private var showWindowlessApps = false
    @AppStorage(SettingKey.currentDisplayOnly) private var currentDisplayOnly = false
    @AppStorage(SettingKey.excludedApps) private var excludedAppsStorage = ""

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Section("Permissions") {
                    PermissionRow(name: "Accessibility", isGranted: Permissions.hasAccessibility) {
                        Permissions.requestAccessibility()
                    }
                    PermissionRow(name: "Screen Recording", isGranted: Permissions.hasScreenRecording) {
                        Permissions.requestScreenRecording()
                    }
                    Text("Screen Recording is only used for window previews. It applies after relaunching Swivel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Switcher") {
                Picker("Show on", selection: $displayTarget) {
                    ForEach(DisplayTarget.allCases) { Text($0.label).tag($0) }
                }
                Picker("Search hotkey", selection: $searchHotkey) {
                    ForEach(SearchHotkey.allCases) { Text($0.label).tag($0) }
                }
                Picker("Theme", selection: $theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Key hints", isOn: $keyHints)
                Toggle("Always show preview", isOn: $showPreview)
            }

            Section("Windows") {
                Toggle("Windows on other Spaces", isOn: $allSpaces)
                Toggle("Minimized windows", isOn: $showMinimized)
                Toggle("Windows of hidden apps", isOn: $showHidden)
                Toggle("Apps with no windows", isOn: $showWindowlessApps)
                Toggle("Only windows on the switcher's display", isOn: $currentDisplayOnly)
            }

            Section("Excluded apps") {
                ForEach(excludedApps.sorted(), id: \.self) { name in
                    LabeledContent(name) {
                        Button("Remove") { setExcluded(name, false) }
                    }
                }
                Menu("Exclude an app") {
                    ForEach(excludableApps, id: \.self) { name in
                        Button(name) { setExcluded(name, true) }
                    }
                }
            }

            Section("Keys") {
                KeyRow(keys: "⌘ Tab", action: "All windows")
                KeyRow(keys: "⌘ `", action: "Windows of the current app")
                KeyRow(keys: "⇧", action: "Reverse")
                KeyRow(keys: "⌘ hint", action: "Jump to an app, repeat for its next window")
                KeyRow(keys: "Space (hold)", action: "Preview window")
                KeyRow(keys: "⌘ ⇧ W", action: "Close window")
                KeyRow(keys: "⌘ ⇧ M", action: "Minimize window")
                KeyRow(keys: "⌘ ⇧ H", action: "Hide app")
                KeyRow(keys: "⌘ ⇧ Q", action: "Quit app")
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var excludedApps: Set<String> {
        ExcludedApps.decode(excludedAppsStorage)
    }

    private var excludableApps: [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .filter { !excludedApps.contains($0) }
            .sorted()
    }

    private func setExcluded(_ name: String, _ excluded: Bool) {
        var names = excludedApps
        if excluded {
            names.insert(name)
        } else {
            names.remove(name)
        }
        excludedAppsStorage = ExcludedApps.encode(names)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

private struct PermissionRow: View {
    let name: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent(name) {
            if isGranted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Grant", action: request)
            }
        }
    }
}

private struct KeyRow: View {
    let keys: String
    let action: String

    var body: some View {
        LabeledContent(action) {
            Text(keys).monospaced()
        }
    }
}
