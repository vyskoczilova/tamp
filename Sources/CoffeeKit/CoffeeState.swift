import Foundation

/// How a caffeination session was started.
public enum CoffeeMode: String, Codable, Sendable {
    /// Stays awake until explicitly turned off.
    case indefinite
    /// Stays awake for a fixed duration (`caffeinate -t`).
    case timed
}

/// Which kinds of sleep are being prevented. Mirrors `caffeinate` flags.
public struct SleepFlags: Codable, Equatable, Sendable {
    /// `-d` — prevent the display from sleeping.
    public var display: Bool
    /// `-i` — prevent the system from idle sleeping.
    public var system: Bool
    /// `-m` — prevent the disk from idle sleeping.
    public var disk: Bool

    public init(display: Bool = true, system: Bool = true, disk: Bool = false) {
        self.display = display
        self.system = system
        self.disk = disk
    }

    /// The `caffeinate` flag arguments these settings map to.
    public var caffeinateArguments: [String] {
        var args: [String] = []
        if display { args.append("-d") }
        if system { args.append("-i") }
        if disk { args.append("-m") }
        return args
    }
}

/// The persisted, shared source of truth for the menu bar app and the CLI.
public struct CoffeeState: Codable, Equatable, Sendable {
    public var active: Bool
    /// PID of the running `caffeinate` process, if any.
    public var pid: Int32?
    public var mode: CoffeeMode?
    public var startedAt: Date?
    /// When a timed session ends. Nil for indefinite sessions.
    public var endsAt: Date?
    public var flags: SleepFlags

    public init(
        active: Bool = false,
        pid: Int32? = nil,
        mode: CoffeeMode? = nil,
        startedAt: Date? = nil,
        endsAt: Date? = nil,
        flags: SleepFlags = SleepFlags()
    ) {
        self.active = active
        self.pid = pid
        self.mode = mode
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.flags = flags
    }

    /// The inactive state, preserving the desired sleep flags.
    public static func inactive(flags: SleepFlags = SleepFlags()) -> CoffeeState {
        CoffeeState(active: false, flags: flags)
    }

    /// Seconds remaining for a timed session, or nil if indefinite/inactive.
    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard active, let endsAt else { return nil }
        return max(0, endsAt.timeIntervalSince(now))
    }
}
