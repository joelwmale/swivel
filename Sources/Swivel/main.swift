import AppKit

if CommandLine.arguments.contains(Permissions.screenRecordingProbeFlag) {
    exit(Permissions.hasScreenRecording ? 0 : 1)
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
