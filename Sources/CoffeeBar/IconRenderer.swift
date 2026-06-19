import AppKit
import CoffeeKit

/// Turns an `IconStyle` into a menu-bar `NSImage` — the single place that
/// resolves custom SVG template artwork (bundled via `Bundle.module`) and falls
/// back to SF Symbols. Both the live status item and the settings preview go
/// through here so they never disagree.
enum IconRenderer {
    /// - active: caffeinated state. Custom styles ship an outline/filled pair, so
    ///   the inactive state loads the outline asset and the active state the
    ///   filled one (see `IconStyle.customAsset(active:)`).
    /// - pointSize: square render size in points (~18 for the menu bar).
    static func image(for style: IconStyle, active: Bool, pointSize: CGFloat) -> NSImage? {
        if let custom = customImage(style.customAsset(active: active), pointSize: pointSize) {
            // Some outline (inactive) variants have thin lines that read faintly
            // at 18px; thicken just those so the off-state stays legible.
            if let weight = emboldenWeight(style, active: active) {
                return emboldened(custom, pointSize: pointSize, weight: weight)
            }
            return custom
        }
        return symbolImage(for: style, active: active)
    }

    /// Stroke-thickening weight for a style's outline state, or nil for none.
    /// Only the inactive (non-selected) outline is emboldened.
    private static func emboldenWeight(_ style: IconStyle, active: Bool) -> CGFloat? {
        guard !active else { return nil }
        switch style {
        case .pourOver: return 0.6
        case .pot, .filter: return 0.2
        default: return nil
        }
    }

    private static func customImage(_ asset: String?, pointSize: CGFloat) -> NSImage? {
        guard let asset,
              let url = Bundle.module.url(forResource: asset, withExtension: "svg", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }

    /// Thicken a template image's strokes by stamping it at small offsets in
    /// every direction — a cheap way to embolden thin outline artwork.
    private static func emboldened(_ image: NSImage, pointSize: CGFloat, weight: CGFloat = 0.6) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let out = NSImage(size: size)
        out.lockFocus()
        let offsets: [(CGFloat, CGFloat)] = [(-1, 0), (1, 0), (0, -1), (0, 1),
                                             (-1, -1), (1, 1), (-1, 1), (1, -1)]
        for (dx, dy) in offsets {
            image.draw(in: NSRect(x: dx * weight, y: dy * weight, width: pointSize, height: pointSize),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        out.isTemplate = true
        return out
    }

    private static func symbolImage(for style: IconStyle, active: Bool) -> NSImage? {
        let symbol = active ? style.activeSymbol : style.inactiveSymbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: style.label)
            ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: style.label)
        image?.isTemplate = true
        return image
    }
}
