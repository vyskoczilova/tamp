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
            return custom
        }
        return symbolImage(for: style, active: active)
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

    private static func symbolImage(for style: IconStyle, active: Bool) -> NSImage? {
        let symbol = active ? style.activeSymbol : style.inactiveSymbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: style.label)
            ?? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: style.label)
        image?.isTemplate = true
        return image
    }
}
