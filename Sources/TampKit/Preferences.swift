import Foundation

/// User preferences persisted in `UserDefaults` (shared by app and CLI via a
/// suite name so both processes read the same values).
public struct Preferences {
    private let defaults: UserDefaults

    private enum Key {
        static let display = "preventDisplaySleep"
        static let system = "preventSystemSleep"
        static let disk = "preventDiskSleep"
        static let acPower = "preventSleepOnAC"
        static let wake = "wakeDisplayOnStart"
        static let iconStyle = "iconStyle"
        static let notifyOnEnd = "notifyOnSessionEnd"
    }

    /// The shared suite used by both `tamp` and `TampBar`.
    public static let suiteName = "cz.kybernaut.tamp"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Preferences.suiteName) ?? .standard
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.display: true,
            Key.system: true,
            Key.disk: false,
            Key.acPower: false,
            Key.wake: false,
            Key.notifyOnEnd: false,
        ])
    }

    public var sleepFlags: SleepFlags {
        get {
            SleepFlags(
                display: defaults.bool(forKey: Key.display),
                system: defaults.bool(forKey: Key.system),
                disk: defaults.bool(forKey: Key.disk),
                acPower: defaults.bool(forKey: Key.acPower),
                wake: defaults.bool(forKey: Key.wake)
            )
        }
        nonmutating set {
            defaults.set(newValue.display, forKey: Key.display)
            defaults.set(newValue.system, forKey: Key.system)
            defaults.set(newValue.disk, forKey: Key.disk)
            defaults.set(newValue.acPower, forKey: Key.acPower)
            defaults.set(newValue.wake, forKey: Key.wake)
        }
    }

    /// Opt-in "session ended" notification (posted by the menu bar app).
    public var notifyOnSessionEnd: Bool {
        get { defaults.bool(forKey: Key.notifyOnEnd) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifyOnEnd) }
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
