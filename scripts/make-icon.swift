// Renders Resources/AppIcon.icns: a dark translucent card with the Claude-orange sparkle.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let card = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: card, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.20, green: 0.18, blue: 0.17, alpha: 1),
                        NSColor(red: 0.09, green: 0.08, blue: 0.08, alpha: 1)])!.draw(in: path, angle: -90)

    // Three faint "session rows" in the lower part of the card.
    let orange = NSColor(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    for (i, width) in [520.0, 430.0, 360.0].enumerated() {
        let y = (300 - Double(i) * 78) * s
        NSColor.white.withAlphaComponent(i == 0 ? 0.22 : 0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: 290 * s, y: y, width: width * s, height: 30 * s), xRadius: 15 * s, yRadius: 15 * s).fill()
        (i == 0 ? NSColor(red: 0.25, green: 0.73, blue: 0.31, alpha: 1) : NSColor.white.withAlphaComponent(0.3)).setFill()
        NSBezierPath(ovalIn: NSRect(x: 215 * s, y: y, width: 30 * s, height: 30 * s)).fill()
    }

    // Sparkle.
    let config = NSImage.SymbolConfiguration(pointSize: 330 * s, weight: .bold)
        .applying(.init(paletteColors: [orange]))
    if let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let r = NSRect(x: (1024 * s - symbol.size.width) / 2, y: 460 * s, width: symbol.size.width, height: symbol.size.height)
        symbol.draw(in: r)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/AppIcon-1024.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
