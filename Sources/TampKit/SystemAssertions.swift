import Foundation

/// An external `caffeinate` process keeping the Mac awake, with its resolved
/// launcher (parent process) so front-ends can say *who* is caffeinating —
/// e.g. "bash (pid 1234)" — instead of a flat "another app".
public struct ExternalCaffeination: Codable, Equatable, Sendable {
    /// PID of the `caffeinate` process itself.
    public let pid: Int32
    /// PID of the process that launched it, nil when unreadable (gone mid-scan
    /// or belongs to another user).
    public let parentPID: Int32?
    /// Name of the parent process, nil when unreadable.
    public let parentName: String?

    public init(pid: Int32, parentPID: Int32?, parentName: String?) {
        self.pid = pid
        self.parentPID = parentPID
        self.parentName = parentName
    }

    /// Human-readable launcher, shared by both front-ends so the wording never
    /// drifts: "bash (pid 1234)", or an honest "orphaned" when the launcher
    /// already exited and the caffeinate was reparented to launchd (pid 1) —
    /// naming launchd would misattribute the wake lock.
    public var sourceDescription: String {
        guard let parentPID else { return "an unidentified process (caffeinate pid \(pid))" }
        if parentPID <= 1 { return "an orphaned caffeinate (pid \(pid) — parent exited)" }
        guard let parentName else { return "pid \(parentPID)" }
        return "\(parentName) (pid \(parentPID))"
    }
}

extension [ExternalCaffeination] {
    /// One-line summary for status displays: the first source, plus a count
    /// when several caffeinates are alive. Falls back to "another app" for an
    /// empty list (defensive — `phase()` never builds an empty one), so the
    /// fallback wording lives here and not in each front-end.
    public var sourceSummary: String {
        guard let first else { return "another app" }
        return count > 1 ? "\(first.sourceDescription) and \(count - 1) more" : first.sourceDescription
    }
}

/// Checks whether any caffeinate process is alive on the system, regardless
/// of who started it. Used only when Tamp's own state is inactive — if
/// Tamp has a live session, `TampState.active` takes precedence and this
/// is never consulted. The scan runs in-process via libproc (callable straight
/// from Swift): the front-ends poll this while idle, and spawning a `pgrep`
/// subprocess every few seconds is needless fork/exec churn. Parent resolution
/// (`proc_pidinfo`) only runs for PIDs that matched "caffeinate", so the
/// common no-caffeinate scan costs exactly what it did before.
public enum SystemAssertions {
    /// Name of the live process with the given PID, or nil if it's gone.
    static func processName(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// Parent PID of the live process, or nil if unreadable.
    static func parentPID(of pid: pid_t) -> pid_t? {
        // PROC_PIDTBSDINFO flavor (sys/proc_info.h); spelled numerically
        // because the macro doesn't reliably import into Swift.
        let flavor: Int32 = 3
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, flavor, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// All live caffeinate processes with their launchers resolved. Empty means
    /// nothing is keeping the Mac awake.
    public static func externalCaffeinations() -> [ExternalCaffeination] {
        // proc_listallpids returns the number of PIDs (estimate when the
        // buffer is nil, entries written when it's provided).
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64) // headroom for new arrivals
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).compactMap { pid in
            guard pid > 0, processName(of: pid) == "caffeinate" else { return nil }
            let ppid = parentPID(of: pid)
            return ExternalCaffeination(
                pid: pid,
                parentPID: ppid,
                parentName: ppid.flatMap { processName(of: $0) }
            )
        }
    }
}
