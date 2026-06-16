import AppKit
import CoffeeKit

/// Turns an `IconStyle` into a menu-bar `NSImage` — the single place that
/// resolves custom SVG template artwork (bundled via `Bundle.module`) and falls
/// back to SF Symbols. Both the live status item and the settings preview go
/// through here so they never disagree.
enum IconRenderer {
    /// - active: caffeinated state. Custom art has no filled/outline pair, so the
    ///   inactive state is the same silhouette drawn dimmed.
    /// - pointSize: square render size in points (~18 for the menu bar).
    static func image(for style: IconStyle, active: Bool, pointSize: CGFloat) -> NSImage? {
        if let custom = customImage(for: style, pointSize: pointSize) {
            return active ? custom : dimmed(custom, pointSize: pointSize)
        }
        return symbolImage(for: style, active: active)
    }

    private static func customImage(for style: IconStyle, pointSize: CGFloat) -> NSImage? {
        guard let asset = style.customAssetName,
              let url = Bundle.module.url(forResource: asset, withExtension: "svg", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    private static func symbolImage(for style: IconStyle, active: Bool) -> NSImage? {
        let symbol = active ? style.activeSymbol : style.inactiveSymbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: style.label)
            ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: style.label)
        image?.isTemplate = true
        return image
    }

    /// Redraw a template image at reduced opacity to signal the inactive state.
    private static func dimmed(_ image: NSImage, pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: .zero, operation: .sourceOver, fraction: 0.4)
        out.unlockFocus()
        out.isTemplate = true
        return out
    }
}
