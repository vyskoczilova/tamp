import Foundation

/// Selectable menu bar icon styles. `.cup` renders from an SF Symbol; the
/// brewing styles render from bundled custom SVG template artwork (see
/// `customAssetName`), with an SF Symbol fallback if the asset can't load.
public enum IconStyle: String, CaseIterable, Codable, Sendable {
    case cup
    case mug
    case toGo
    case pourOver
    case filter
    case pot
    case tamper

    /// Human-readable label for menus and CLI output.
    public var label: String {
        switch self {
        case .cup: return "Cup"
        case .mug: return "Mug"
        case .toGo: return "To-Go"
        case .pourOver: return "Pour-Over"
        case .filter: return "Filter"
        case .pot: return "Pot"
        case .tamper: return "Tamper"
        }
    }

    /// Basename of the bundled SVG template asset for the given state, or nil for
    /// SF-Symbol styles. Custom styles ship a pair: an outline variant for the
    /// inactive state and a filled variant for the active state. Filenames are
    /// the original noun-project IDs (kept verbatim).
    public func customAsset(active: Bool) -> String? {
        switch self {
        case .cup: return nil
        case .mug: return active ? "noun-coffee-7693728" : "noun-coffee-7693726"
        case .toGo: return active ? "noun-coffee-8248582" : "noun-coffee-8248581"
        case .pourOver: return active ? "noun-hario-v60-pour-over-1025641" : "noun-hario-v60-pour-over-1025640"
        case .filter: return active ? "noun-coffee-filter-7855449" : "noun-coffee-filter-7855404"
        case .pot: return active ? "noun-coffee-pot-6832059" : "noun-coffee-pot-6809962"
        case .tamper: return active ? "noun-coffee-tamper-8021081" : "noun-coffee-tamper-7366163"
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
