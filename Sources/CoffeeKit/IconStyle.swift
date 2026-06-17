import Foundation

/// Selectable menu bar icon styles. `.cup` renders from an SF Symbol; the
/// brewing styles render from bundled custom SVG template artwork (see
/// `customAsset(active:)`), with an SF Symbol fallback if the asset can't load.
/// Cases are ordered alphabetically by `label` (the order shown in menus/CLI).
public enum IconStyle: String, CaseIterable, Codable, Sendable {
    // Keep cases sorted alphabetically by `label` — `allCases` drives menu/CLI order.
    case cup
    case filter
    case mug
    case pot
    case pourOver
    case tamper
    case toGo

    /// The style used when no preference has been set yet.
    public static let `default`: IconStyle = .tamper

    /// Human-readable label for menus and CLI output.
    public var label: String {
        switch self {
        case .cup: return "Cup"
        case .filter: return "Filter"
        case .mug: return "Mug"
        case .pot: return "Pot"
        case .pourOver: return "Pour-Over"
        case .tamper: return "Tamper"
        case .toGo: return "To-Go"
        }
    }

    /// Basename of the bundled SVG template asset for the given state, or nil for
    /// SF-Symbol styles. Custom styles ship a pair: an outline variant for the
    /// inactive state and a filled variant for the active state. Filenames are
    /// the original noun-project IDs (kept verbatim).
    public func customAsset(active: Bool) -> String? {
        switch self {
        case .cup: return nil
        case .filter: return active ? "noun-coffee-filter-7855449" : "noun-coffee-filter-7855404"
        case .mug: return active ? "noun-coffee-7693728" : "noun-coffee-7693726"
        case .pot: return active ? "noun-coffee-pot-6832059" : "noun-coffee-pot-6809962"
        case .pourOver: return active ? "noun-hario-v60-pour-over-1025641" : "noun-hario-v60-pour-over-1025640"
        case .tamper: return active ? "noun-coffee-tamper-8021081" : "noun-coffee-tamper-7366163"
        case .toGo: return active ? "noun-coffee-8248582" : "noun-coffee-8248581"
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
