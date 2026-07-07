import Foundation

/// The engine. Wraps `/usr/bin/caffeinate`, owns the shared state, and keeps it
/// reconciled with reality (a recorded PID that no longer exists means inactive).
///
/// Two independent things can want the Mac awake: the single manual session
/// (`on`/`for`/`until`) and any number of named holds (`hold`/`release`). Both
/// share one tracked caffeinate process; it runs while
/// `active || !holders.isEmpty`. All decisions that depend on current state
/// (am I the first hold? the last release?) happen inside `StateStore.mutate`,
/// so concurrent callers from different processes serialize safely.
public final class CaffeinateController {
    public static let caffeinatePath = "/usr/bin/caffeinate"

    private let store: StateStore
    private let preferences: Preferences

    public init(store: StateStore = StateStore(), preferences: Preferences = Preferences()) {
        self.store = store
        self.preferences = preferences
    }

    /// Current state, reconciled against the running process. Read-only unless
    /// something actually drifted (dead PID, expired hold) — the common path is
    /// a single coordinated read plus one process-name check.
    public func status() -> TampState {
        let state = store.loadRaw()
        guard needsSettle(state) else { return state }
        return store.mutate { state in
            do { try self.settle(&state) } catch {
                kitLog.error("status settle failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Start a manual session. `duration` nil means indefinite; otherwise timed.
    /// `flags` overrides the saved preferences for this session when provided.
    /// Holds are preserved — a manual session layers on top of them.
    @discardableResult
    public func start(duration seconds: Int? = nil, flags: SleepFlags? = nil) throws -> TampState {
        let effectiveFlags = flags ?? preferences.sleepFlags
        var thrown: Error?
        let state = store.mutate { state in
            // Replace any existing tracked process (manual or holder-spawned)
            // so the new flags/duration take effect.
            if let pid = state.pid, self.isTrackedCaffeinate(pid) {
                kill(pid, SIGTERM)
            }
            let now = Date()
            state.holders.removeAll { $0.isExpired(now: now) }
            do {
                let pid = try self.spawnCaffeinate(flags: effectiveFlags, seconds: seconds)
                state = TampState(
                    active: true,
                    pid: pid,
                    endsAt: seconds.map { now.addingTimeInterval(TimeInterval($0)) },
                    flags: effectiveFlags,
                    holders: state.holders
                )
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
        return state
    }

    /// Register a named hold. Starts caffeinate if nothing is running yet;
    /// otherwise just records the id. Re-holding the same id is a refresh
    /// (idempotent; updates the TTL), so refcounting is by name, not a counter
    /// a double-firing hook could inflate. `ttl` seconds, when given, make the
    /// hold self-expire so a crashed caller can't pin the Mac awake forever.
    @discardableResult
    public func hold(_ id: String, ttl seconds: Int? = nil) throws -> TampState {
        var thrown: Error?
        let state = store.mutate { state in
            let now = Date()
            state.holders.removeAll { $0.id == id }
            state.holders.append(TampState.Holder(
                id: id,
                expiresAt: seconds.map { now.addingTimeInterval(TimeInterval($0)) }
            ))
            do { try self.settle(&state, now: now) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return state
    }

    /// Remove a named hold. Stops caffeinate only if this was the last hold
    /// and no manual session is active. Releasing an unknown id is a no-op
    /// (idempotent), so double-firing hooks are harmless.
    @discardableResult
    public func release(_ id: String) throws -> TampState {
        var thrown: Error?
        let state = store.mutate { state in
            state.holders.removeAll { $0.id == id }
            do { try self.settle(&state) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return state
    }

    /// Drop every hold — the escape hatch for a caller that died without
    /// releasing. A manual session, if any, keeps running.
    @discardableResult
    public func releaseAll() -> TampState {
        store.mutate { state in
            state.holders.removeAll()
            // No spawn can happen with zero holders, so settle cannot throw here.
            try? self.settle(&state)
        }
    }

    /// Persist new sleep preferences. If a session is live, restart it so the
    /// flags take effect immediately while preserving any remaining time.
    @discardableResult
    public func applyFlags(_ flags: SleepFlags) throws -> TampState {
        preferences.sleepFlags = flags
        let current = status()
        if current.active {
            return try start(duration: current.remaining().map { Int($0) }, flags: flags)
        }
        guard !current.liveHolders().isEmpty else { return current }
        // Holder-kept process: bounce it so the new flags apply.
        var thrown: Error?
        let state = store.mutate { state in
            if let pid = state.pid, self.isTrackedCaffeinate(pid) {
                kill(pid, SIGTERM)
                state.pid = nil
            }
            do { try self.settle(&state) } catch { thrown = error }
        }
        if let thrown { throw thrown }
        return state
    }

    /// Stop everything — the manual session AND all holds. An explicit user
    /// "off" wins over background holders; hook-based holders re-register on
    /// their next natural trigger. Safe to call when already inactive.
    @discardableResult
    public func stop() -> TampState {
        store.mutate { state in
            if let pid = state.pid, self.isTrackedCaffeinate(pid) {
                kill(pid, SIGTERM)
            }
            state = TampState.inactive(flags: state.flags)
        }
    }

    /// Toggle: anything keeping the Mac awake through Tamp (manual session or
    /// holds) → stop it all; otherwise start an indefinite manual session.
    @discardableResult
    public func toggle() throws -> TampState {
        let current = status()
        if current.active || !current.liveHolders().isEmpty {
            return stop()
        }
        return try start()
    }

    // MARK: - Reconciliation

    /// Bring the persisted state and the real process into agreement. MUST run
    /// inside a `StateStore.mutate` block — that is what makes first-hold /
    /// last-release decisions race-free across processes. Handles, in order:
    /// expired holds pruned; a dead manual session cleared (timer elapsed,
    /// manual kill, recycled PID); a missing process respawned while holds
    /// remain (also how holds survive a timed session's `-t` expiry); a
    /// process nothing wants anymore killed.
    private func settle(_ state: inout TampState, now: Date = Date()) throws {
        state.holders.removeAll { $0.isExpired(now: now) }
        let pidLive = state.pid.map(isTrackedCaffeinate) == true
        if state.active && !pidLive {
            state.active = false
            state.endsAt = nil
            state.pid = nil
        }
        let shouldRun = state.active || !state.holders.isEmpty
        if shouldRun && !pidLive {
            // Only holds can reach here (a dead manual session was cleared
            // above): spawn indefinite, with the currently preferred flags.
            state.flags = preferences.sleepFlags
            state.pid = try spawnCaffeinate(flags: state.flags)
            state.endsAt = nil
        } else if !shouldRun {
            if let pid = state.pid, pidLive {
                kill(pid, SIGTERM)
            }
            state.pid = nil
            state.endsAt = nil
        }
    }

    /// Cheap pre-check so `status()` only takes write coordination when the
    /// state actually drifted from reality.
    private func needsSettle(_ state: TampState, now: Date = Date()) -> Bool {
        if state.holders.contains(where: { $0.isExpired(now: now) }) { return true }
        let pidLive = state.pid.map(isTrackedCaffeinate) == true
        let shouldRun = state.active || !state.holders.isEmpty
        if shouldRun != pidLive { return true }
        if !shouldRun && state.pid != nil { return true }
        return false
    }

    // MARK: - Process management

    /// Spawn a detached caffeinate and return its PID. Indefinite when
    /// `seconds` is nil.
    private func spawnCaffeinate(flags: SleepFlags, seconds: Int? = nil) throws -> Int32 {
        var args = flags.caffeinateArguments
        if args.isEmpty { args.append("-i") } // Never launch a no-op caffeinate.
        if let seconds { args.append(contentsOf: ["-t", String(seconds)]) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.caffeinatePath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }

    /// PIDs are recycled (reboot, timer expiry), so a recorded PID must never be
    /// trusted — let alone killed — unless the process behind it is still a
    /// caffeinate.
    private func isTrackedCaffeinate(_ pid: Int32) -> Bool {
        SystemAssertions.processName(of: pid) == "caffeinate"
    }
}
