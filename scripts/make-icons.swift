// Renders the Suspenders icon (dusk gradient + crescent moon) at the sizes we need.
// Usage: swift scripts/make-icons.swift
import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.23, cornerHeight: rect.width * 0.23, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    let colors = [NSColor(red: 0.07, green: 0.05, blue: 0.17, alpha: 1).cgColor,
                  NSColor(red: 0.21, green: 0.16, blue: 0.42, alpha: 1).cgColor,
                  NSColor(red: 0.88, green: 0.54, blue: 0.36, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s * 0.3, y: 0), options: [])

    // crescent: moon circle minus offset circle
    let r = s * 0.24
    let c = CGPoint(x: s * 0.5, y: s * 0.54)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.08, color: NSColor(red: 1, green: 0.95, blue: 0.84, alpha: 0.7).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(NSColor(red: 0.99, green: 0.95, blue: 0.84, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    ctx.setBlendMode(.clear)
    let o = CGPoint(x: c.x + r * 0.5, y: c.y + r * 0.32)
    ctx.fillEllipse(in: CGRect(x: o.x - r * 0.92, y: o.y - r * 0.92, width: r * 1.84, height: r * 1.84))
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let ext = root.appendingPathComponent("extension/icons")
try FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
for size in [16, 48, 128] {
    try render(size: size).write(to: ext.appendingPathComponent("icon\(size).png"))
}

let iconset = root.appendingPathComponent("helper/Resources/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("Icons written.")
