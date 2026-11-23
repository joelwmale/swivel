import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tap = EventTap()
    private let controller = SwitcherController()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        NativeSwitcher.restoreOnAbnormalExit()
        installStatusItem()

        if Permissions.hasAccessibility {
            startSwitching()
            return
        }

        showSettings()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            if Permissions.hasAccessibility {
                self?.startSwitching()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeSwitcher.setEnabled(true)
    }

    private func startSwitching() {
        // The system switcher is only turned off once ours can receive keys.
        guard tap.start() else {
            return
        }

        permissionTimer?.invalidate()
        permissionTimer = nil
        tap.handler = { [controller] type, event in controller.handle(type, event) }
        NativeSwitcher.setEnabled(false)
        WindowStore.shared.start()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "CmdTab")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CmdTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "CmdTab"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
