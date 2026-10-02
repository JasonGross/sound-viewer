// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt rounded square centred in 1024.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.10, green: 0.11, blue: 0.24, alpha: 1),
                    NSColor(red: 0.13, green: 0.30, blue: 0.45, alpha: 1)])!.draw(in: shape, angle: 90)

// Three lanes of bars; one lane has a single loud spike, the "mystery sound".
let lanes: [(y: Double, heights: [Double], color: NSColor)] = [
    (690, [10, 18, 34, 52, 40, 26, 44, 60, 48, 30, 20, 34, 46, 30, 16, 10], NSColor(red: 0.40, green: 0.75, blue: 1.0, alpha: 1)),
    (512, [6, 6, 6, 6, 6, 6, 8, 120, 96, 18, 6, 6, 6, 6, 6, 6], NSColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1)),
    (334, [16, 28, 20, 36, 30, 22, 14, 10, 18, 30, 42, 34, 24, 18, 26, 14], NSColor(red: 0.45, green: 0.90, blue: 0.65, alpha: 1)),
]
let barWidth = 26.0, gap = 14.0
let startX = 512 - (Double(lanes[0].heights.count) * (barWidth + gap) - gap) / 2
for lane in lanes {
    lane.color.setFill()
    for (i, h) in lane.heights.enumerated() {
        let x = startX + Double(i) * (barWidth + gap)
        NSBezierPath(roundedRect: NSRect(x: x, y: lane.y - h, width: barWidth, height: h * 2),
                     xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    }
}

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = iconset.appendingPathComponent("master.png")
try png.write(to: master)

func run(_ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = FileHandle.nullDevice
    try p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("\(args) failed") }
}
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try run(["/usr/bin/sips", "-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try fm.removeItem(at: master)
try run(["/usr/bin/iconutil", "-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"])
print("Wrote Resources/AppIcon.icns")
