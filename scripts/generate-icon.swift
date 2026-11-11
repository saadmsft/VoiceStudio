import AppKit
import CoreGraphics
import Foundation

let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetPath)
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)

    // Rounded macOS squircle background
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        CGColor(red: 0.06, green: 0.08, blue: 0.13, alpha: 1.0),
        CGColor(red: 0.11, green: 0.15, blue: 0.24, alpha: 1.0)
    ] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Glowing Studio Waveform Bars
    let barHeights: [CGFloat] = [0.22, 0.38, 0.58, 0.44, 0.68, 0.50, 0.32]
    let barWidth = s * 0.062
    let gap = s * 0.036
    let totalW = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * gap
    let startX = (s - totalW) / 2.0

    for (idx, hNorm) in barHeights.enumerated() {
        let bh = s * hNorm
        let bx = startX + CGFloat(idx) * (barWidth + gap)
        let by = (s - bh) / 2.0
        let barRect = CGRect(x: bx, y: by, width: barWidth, height: bh)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth * 0.5, cornerHeight: barWidth * 0.5, transform: nil)
        ctx.addPath(barPath)
        if idx < 3 {
            ctx.setFillColor(CGColor(red: 0.98, green: 0.68, blue: 0.22, alpha: 0.95))
        } else {
            ctx.setFillColor(CGColor(red: 0.22, green: 0.78, blue: 0.98, alpha: 0.95))
        }
        ctx.fillPath()
    }

    // Subtle border
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let specs: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, filename) in specs {
    let rep = renderIcon(size: px)
    if let png = rep.representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(filename)"))
    }
}
