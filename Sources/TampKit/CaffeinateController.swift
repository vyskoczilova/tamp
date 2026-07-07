import Foundation

/// Why a session operation couldn't apply to the current state.
public enum SessionError: Error, Equatable, CustomStringConvertible {
    case notActive
    case notTimed
    case overCap

    public var description: String {
        switch self {
        case .notActive:
            return "No session is running. Start one with 'on', 'for', or 'until'."
        case .notTimed:
            return "Only timed sessions can be extended."
        case .overCap:
            return "Sessions are capped at 7 days."
        }
    }
}

/// The engine. Wraps `/usr/bin/caffeinate`, owns the shared state, and keeps it
/// reconciled with reality (a recorded PID that no longer exists means inactive).
public final class CaffeinateController {
    public static let caffeinatePath = "/usr/bin/caffeinate"

    private let store: StateStore
    private let preferences: Preferences

    public init(store: StateStore = StateStore(), preferences: Preferences = Preferences()) {
        self.store = store
        self.preferences = preferences
    }

    /// Current state, reconciled against the running process.
    public func status() -> TampState {
        reconcile(store.loadRaw())
    }

    /// Start caffeination. `duration` nil means indefinite; otherwise timed.
    /// `flags` overrides the saved preferences for this session when provided.
    @discardableResult
    public func start(duration seconds: Int? = nil, flags: SleepFlags? = nil) throws -> TampState {
        stop() // Replace any existing session.

        let effectiveFlags = flags ?? preferences.sleepFlags
        var args = effectiveFlags.caffeinateArguments
        if args.isEmpty { args.append("-i") } // Never launch a no-op caffeinate.
        if let seconds { args.append(contentsOf: ["-t", String(seconds)]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let state = TampState(
            active: true,
            pid: process.processIdentifier,
            endsAt: seconds.map { Date().addingTimeInterval(TimeInterval($0)) },
            flags: effectiveFlags
        )
        store.save(state)
        return state
    }

    /// Persist new sleep preferences. If a session is live, restart it so the
    /// flags take effect immediately while preserving any remaining time.
    @discardableResult
    public func applyFlags(_ flags: SleepFlags) throws -> TampState {
        preferences.sleepFlags = flags
        let current = status()
        guard current.active else { return current }
        return try start(duration: current.remaining().map { Int($0) }, flags: flags)
    }

    /// Add time to the current timed session. Restarts the tracked caffeinate
    /// with the new remaining total (same pattern as `applyFlags`), keeping the
    /// session's own flags. The 7-day cap applies to the new total.
    @discardableResult
    public func extend(by seconds: Int) throws -> TampState {
        let current = status()
        guard current.active else { throw SessionError.notActive }
        guard let remaining = current.remaining() else { throw SessionError.notTimed }
        // Compare before adding (like DurationParser's cap check) so absurd
        // inputs can't overflow. Non-positive extensions are rejected too.
        guard seconds > 0, seconds <= DurationParser.maxSeconds - Int(remaining) else {
            throw SessionError.overCap
        }
        return try start(duration: Int(remaining) + seconds, flags: current.flags)
    }

    /// Stop any running session. Safe to call when already inactive.
    @discardableResult
    public func stop() -> TampState {
        let current = store.loadRaw()
        if let pid = current.pid, isTrackedCaffeinate(pid) {
            kill(pid, SIGTERM)
        }
        let inactive = TampState.inactive(flags: current.flags)
        store.save(inactive)
        return inactive
    }

    /// Toggle on (indefinite) or off based on current state.
    @discardableResult
    public func toggle() throws -> TampState {
        if status().active {
            return stop()
        }
        return try start()
    }

    // MARK: - Reconciliation

    /// If the recorded process is gone (manual kill or timer elapsed), correct
    /// the persisted state to inactive.
    private func reconcile(_ state: TampState) -> TampState {
        guard state.active, let pid = state.pid else { return state }
        if isTrackedCaffeinate(pid) {
            return state
        }
        let corrected = TampState.inactive(flags: state.flags)
        store.save(corrected)
        return corrected
    }

    /// PIDs are recycled (reboot, timer expiry), so a recorded PID must never be
    /// trusted — let alone killed — unless the process behind it is still a
    /// caffeinate.
    private func isTrackedCaffeinate(_ pid: Int32) -> Bool {
        SystemAssertions.processName(of: pid) == "caffeinate"
    }
}
