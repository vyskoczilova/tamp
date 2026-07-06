#!/usr/bin/env swift
// Generate Assets/AppIcon.icns from the filled tamper menu-bar SVG:
// a cream tamper glyph on an espresso squircle, with the ~10% transparent
// margin macOS app icons use. Rerun after changing the artwork:
//
//   swift Scripts/make-appicon.swift && git add Assets/AppIcon.icns
import AppKit

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let svgURL = root.appendingPathComponent("Sources/TampBar/Icons/noun-coffee-tamper-8021081.svg")
let iconsetURL = root.appendingPathComponent("build/AppIcon.iconset")
let icnsURL = root.appendingPathComponent("Assets/AppIcon.icns")

guard let svg = NSImage(contentsOf: svgURL) else {
    fputs("cannot load \(svgURL.path)\n", stderr)
    exit(1)
}

let background = NSColor(srgbRed: 0.28, green: 0.17, blue: 0.13, alpha: 1)   // espresso
let glyphColor = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.86, alpha: 1)   // cream

func bitmap(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                     isPlanar: false, colorSpaceName: .deviceRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)!
}

/// Rasterize the SVG alone at an exact pixel size (its alpha is the glyph mask).
func glyphMask(_ px: Int) -> CGImage {
    let rep = bitmap(px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

/// One flat render pass per size: squircle fill, then cream through the glyph's
/// alpha via a CG clip mask — no nested image compositing, no edge bleed.
func renderIcon(px: Int) -> NSBitmapImageRep {
    let rep = bitmap(px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx

    let s = CGFloat(px)
    let side = (s * 0.80).rounded()
    let squircle = NSRect(x: ((s - side) / 2).rounded(), y: ((s - side) / 2).rounded(),
                          width: side, height: side)
    background.setFill()
    NSBezierPath(roundedRect: squircle, xRadius: side * 0.225, yRadius: side * 0.225).fill()

    let g = Int((side * 0.58).rounded())
    let origin = CGFloat((px - g) / 2)
    let cg = ctx.cgContext
    cg.saveGState()
    cg.clip(to: CGRect(x: origin, y: origin, width: CGFloat(g), height: CGFloat(g)),
            mask: glyphMask(g))
    cg.setFillColor(glyphColor.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: s, height: s))
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
try? fm.removeItem(at: iconsetURL)
try! fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try? fm.createDirectory(at: icnsURL.deletingLastPathComponent(), withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = renderIcon(px: base * scale)
        rep.size = NSSize(width: base, height: base)
        try! rep.representation(using: .png, properties: [:])!
            .write(to: iconsetURL.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
print("wrote \(icnsURL.path)")
