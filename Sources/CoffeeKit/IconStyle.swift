import Foundation

/// Selectable menu bar icon styles.
public enum IconStyle: String, CaseIterable, Codable, Sendable {
    case cup
    case pot

    /// Human-readable label for menus and CLI output.
    public var label: String {
        switch self {
        case .cup: return "Cup"
        case .pot: return "Pot"
        }
    }

    /// SF Symbol name for the inactive (not caffeinated) state.
    public var inactiveSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer"
        case .pot: return "cup.and.heat.waves"
        }
    }

    /// SF Symbol name for the active (caffeinated) state.
    public var activeSymbol: String {
        switch self {
        case .cup: return "cup.and.saucer.fill"
        case .pot: return "cup.and.heat.waves.fill"
        }
    }
}
