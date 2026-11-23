// Draws Resources/AppIcon.icns. Run from the repo root: swift Scripts/make-icon.swift
import AppKit

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Apple's icon grid: an 824pt body centred on a 1024pt canvas.
    let unit = CGFloat(pixels) / 1024
    let body = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * unit, yRadius: 185 * unit)

    NSGradient(
        starting: NSColor(red: 0.20, green: 0.20, blue: 0.24, alpha: 1),
        ending: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
    )!.draw(in: shape, angle: -90)

    let rowHeight = 132 * unit
    let rowGap = 44 * unit
    let rowWidth = 560 * unit
    let stackHeight = rowHeight * 3 + rowGap * 2

    for index in 0..<3 {
        let row = NSRect(
            x: body.midX - rowWidth / 2,
            y: body.midY + stackHeight / 2 - rowHeight - CGFloat(index) * (rowHeight + rowGap),
            width: rowWidth,
            height: rowHeight
        )
        let isSelected = index == 1
        (isSelected ? NSColor.systemBlue : NSColor.white.withAlphaComponent(0.16)).setFill()
        NSBezierPath(roundedRect: row, xRadius: 36 * unit, yRadius: 36 * unit).fill()

        let dot = NSRect(x: row.minX + 36 * unit, y: row.midY - 30 * unit, width: 60 * unit, height: 60 * unit)
        NSColor.white.withAlphaComponent(isSelected ? 1 : 0.45).setFill()
        NSBezierPath(roundedRect: dot, xRadius: 16 * unit, yRadius: 16 * unit).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
