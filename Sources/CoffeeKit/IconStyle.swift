import Foundation

/// Selectable menu bar icon styles. `.cup` renders from an SF Symbol; the
/// brewing styles render from bundled custom SVG template artwork (see
/// `customAssetName`), with an SF Symbol fallback if the asset can't load.
public enum IconStyle: String, CaseIterable, Codable, Sendable {
    case cup
    case frenchPress

    /// Human-readable label for menus and CLI output.
    public var label: String {
        switch self {
        case .cup: return "Cup"
        case .frenchPress: return "French Press"
        }
    }

    /// Basename of the bundled SVG template asset, or nil for SF-Symbol styles.
    /// Filenames are the original noun-project IDs (kept verbatim).
    public var customAssetName: String? {
        switch self {
        case .cup: return nil
        case .frenchPress: return "noun-french-press-7820817"
        }
    }

    /// SF Symbol name for the inactive (not caffeinated) state. For custom-art
    /// styles this is only the fallback when the SVG asset fails to load.
    public var inactiveSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer"
        default: return "cup.and.saucer"
        }
    }

    /// SF Symbol name for the active (caffeinated) state. For custom-art styles
    /// this is only the fallback when the SVG asset fails to load.
    public var activeSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer.fill"
        default: return "cup.and.saucer.fill"
        }
    }
}
