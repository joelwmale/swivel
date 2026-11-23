import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingKey.displayTarget) private var displayTarget = DisplayTarget.mouse
    @AppStorage(SettingKey.searchHotkey) private var searchHotkey = SearchHotkey.optionTab
    @AppStorage(SettingKey.font) private var font = SwitcherFont.mono
    @AppStorage(SettingKey.showPreview) private var showPreview = true
    @AppStorage(SettingKey.allSpaces) private var allSpaces = true
    @AppStorage(SettingKey.showMinimized) private var showMinimized = true
    @AppStorage(SettingKey.showHidden) private var showHidden = true
    @AppStorage(SettingKey.showWindowlessApps) private var showWindowlessApps = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
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
                    Text("Screen Recording is only used for window previews. It applies after relaunching CmdTab.")
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
                Picker("Font", selection: $font) {
                    ForEach(SwitcherFont.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Window preview", isOn: $showPreview)
            }

            Section("Windows") {
                Toggle("Windows on other Spaces", isOn: $allSpaces)
                Toggle("Minimized windows", isOn: $showMinimized)
                Toggle("Windows of hidden apps", isOn: $showHidden)
                Toggle("Apps with no windows", isOn: $showWindowlessApps)
            }

            Section("Keys") {
                KeyRow(keys: "⌘ Tab", action: "All windows")
                KeyRow(keys: "⌘ `", action: "Windows of the current app")
                KeyRow(keys: "⇧", action: "Reverse")
                KeyRow(keys: "⌘ W", action: "Close window")
                KeyRow(keys: "⌘ M", action: "Minimize window")
                KeyRow(keys: "⌘ H", action: "Hide app")
                KeyRow(keys: "⌘ Q", action: "Quit app")
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else {
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = !enabled
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
