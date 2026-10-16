// Renders Resources/AppIcon.icns from an SF Symbol. Usage: swift scripts/make_icon.swift
import AppKit

let out = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 0.1, rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1), NSColor(red: 0.42, green: 0.18, blue: 0.55, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225), angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let size = symbol.size
    symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(filePath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
