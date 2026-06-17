import Foundation

/// User preferences persisted in `UserDefaults` (shared by app and CLI via a
/// suite name so both processes read the same values).
public struct Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let display = "preventDisplaySleep"
        static let system = "preventSystemSleep"
        static let disk = "preventDiskSleep"
        static let iconStyle = "iconStyle"
    }

    /// The shared suite used by both `coffee` and `CoffeeBar`.
    public static let suiteName = "cz.kybernaut.coffee"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Preferences.suiteName) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.display: true,
            Key.system: true,
            Key.disk: false,
        ])
    }

    public var sleepFlags: SleepFlags {
        get {
            SleepFlags(
                display: defaults.bool(forKey: Key.display),
                system: defaults.bool(forKey: Key.system),
                disk: defaults.bool(forKey: Key.disk)
            )
        }
        nonmutating set {
            defaults.set(newValue.display, forKey: Key.display)
            defaults.set(newValue.system, forKey: Key.system)
            defaults.set(newValue.disk, forKey: Key.disk)
        }
    }

    public var iconStyle: IconStyle {
        get {
            guard let raw = defaults.string(forKey: Key.iconStyle),
                  let style = IconStyle(rawValue: raw)
            else { return .default }
            return style
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.iconStyle)
        }
    }
}
