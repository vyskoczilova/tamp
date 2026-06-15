import Foundation

/// Selectable menu bar icon styles, including coffee brewing concepts.
public enum IconStyle: String, CaseIterable, Codable, Sendable {
    // Parity with the reference extension.
    case cup
    case mug
    case pot
    case paperCup

    // Brewing concepts (the requested addition).
    case pourOver
    case espresso
    case frenchPress
    case kettle

    /// Human-readable label for menus and CLI output.
    public var label: String {
        switch self {
        case .cup: return "Cup"
        case .mug: return "Mug"
        case .pot: return "Pot"
        case .paperCup: return "Paper Cup"
        case .pourOver: return "Pour-Over"
        case .espresso: return "Espresso"
        case .frenchPress: return "French Press"
        case .kettle: return "Kettle"
        }
    }

    /// SF Symbol name for the inactive (not caffeinated) state.
    public var inactiveSymbol: String {
        switch self {
        case .cup, .paperCup, .pourOver, .espresso, .frenchPress, .kettle:
            return "cup.and.saucer"
        case .mug:
            return "mug"
        case .pot:
            return "cup.and.heat.waves"
        }
    }

    /// SF Symbol name for the active (caffeinated) state.
    public var activeSymbol: String {
        switch self {
        case .cup, .paperCup, .pourOver, .espresso, .frenchPress, .kettle:
            return "cup.and.saucer.fill"
        case .mug:
            return "mug.fill"
        case .pot:
            return "cup.and.heat.waves.fill"
        }
    }
}
