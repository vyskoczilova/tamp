#!/usr/bin/env swift
// Render a contact sheet of icon SVGs so you can see how they read as menu-bar
// template images BEFORE wiring them into IconStyle. Each icon is shown at the
// real menu-bar size (18px) and larger (44px), on a light bar (black) and a
// dark bar (white, inverted) — solid shapes win, thin outlines vanish.
//
// Usage:
//   swift Scripts/icon-preview.swift [svg-dir] [out.png]
//   swift Scripts/icon-preview.swift                       # Icons dir → build/icon-preview.png
//   swift Scripts/icon-preview.swift tmp                   # a folder of candidates
//   swift Scripts/icon-preview.swift tmp /tmp/sheet.png
//
// Then open the PNG (e.g. `open build/icon-preview.png`).
import AppKit

let args = CommandLine.arguments
let svgDir = args.count > 1 ? args[1] : "Sources/CoffeeBar/Icons"
let outPath = args.count > 2 ? args[2] : "build/icon-preview.png"

let files = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: svgDir), includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension == "svg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !files.isEmpty else {
    FileHandle.standardError.write("no .svg files in \(svgDir)\n".data(using: .utf8)!)
    exit(1)
}

let cellW: CGFloat = 240, cellH: CGFloat = 84, cols = 2
let rows = (files.count + cols - 1) / cols
let W = cellW * CGFloat(cols), H = cellH * CGFloat(rows)
let sheet = NSImage(size: NSSize(width: W, height: H))
sheet.lockFocus()
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let lbl: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.black]

// Tint a template image white so we can preview it on a dark menu bar.
func whiteTinted(_ img: NSImage) -> NSImage {
    let out = NSImage(size: img.size); out.lockFocus()
    img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set(); NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
    out.unlockFocus(); return out
}

for (i, url) in files.enumerated() {
    let cx = CGFloat(i % cols) * cellW
    let cy = H - CGFloat(i / cols + 1) * cellH
    let iconH = cellH - 16
    NSColor.white.setFill(); NSRect(x: cx, y: cy, width: cellW/2, height: iconH).fill()
    NSColor.black.setFill(); NSRect(x: cx+cellW/2, y: cy, width: cellW/2, height: iconH).fill()
    NSColor(white: 0.92, alpha: 1).setFill(); NSRect(x: cx, y: cy+iconH, width: cellW, height: 16).fill()
    let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "noun-", with: "")
    (name as NSString).draw(at: NSPoint(x: cx+5, y: cy+iconH+3), withAttributes: lbl)
    guard let img = NSImage(contentsOf: url) else { continue }
    let smallY = cy + (iconH-18)/2, bigY = cy + (iconH-44)/2
    func drawPair(_ image: NSImage, dx: CGFloat) {
        image.draw(in: NSRect(x: cx+dx+14, y: smallY, width: 18, height: 18))
        image.draw(in: NSRect(x: cx+dx+44, y: bigY, width: 44, height: 44))
    }
    drawPair(img, dx: 0)                       // light bar (black, as-is)
    drawPair(whiteTinted(img), dx: cellW/2)    // dark bar (inverted white)
}
sheet.unlockFocus()

try? FileManager.default.createDirectory(at: URL(fileURLWithPath: outPath).deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)  (\(files.count) icons — light bar | dark bar, 18px + 44px)")
