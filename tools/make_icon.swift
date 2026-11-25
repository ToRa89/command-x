#!/usr/bin/env swift
// Renders the app icon: macOS "command" glyph (SF Symbol) on a glassy gradient tile.
// Usage: swift tools/make_icon.swift CommandX/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: tile is 824/1024 of the canvas, centered
    let tile = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    // drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill(); path.fill()
    ctx.restoreGState()

    // base gradient: deep blue -> violet
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.42, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.42, green: 0.20, blue: 0.86, alpha: 1)])!
        .draw(in: tile, angle: -60)

    // glass sheen: soft light from the top
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.38), NSColor.white.withAlphaComponent(0.0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

    // command glyph
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.46, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "command", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let g = NSImage(size: sym.size)
        g.lockFocus()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceAtop)
        g.unlockFocus()
        let r = NSRect(x: s / 2 - g.size.width / 2, y: s / 2 - g.size.height / 2,
                       width: g.size.width, height: g.size.height)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.02,
                      color: NSColor.black.withAlphaComponent(0.30).cgColor)
        g.draw(in: r)
        ctx.restoreGState()
    }

    // thin inner rim for the glass edge
    NSGraphicsContext.current?.cgContext.resetClip()
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: s * 0.002, dy: s * 0.002),
                           xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    rim.lineWidth = max(1, s * 0.004); rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// file names must match Contents.json of the appiconset
let files: [(String, Int)] = [("16.png", 16), ("32.png", 32), ("32 1.png", 32), ("64.png", 64),
                              ("128.png", 128), ("256.png", 256), ("256 1.png", 256),
                              ("512.png", 512), ("512 1.png", 512), ("1024.png", 1024)]
for (name, px) in files {
    try! render(size: px).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("wrote \(files.count) icons to \(outDir)")
