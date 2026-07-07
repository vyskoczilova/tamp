import Foundation

/// Checks whether any caffeinate process is alive on the system, regardless
/// of who started it. Used only when Tamp's own state is inactive — if
/// Tamp has a live session, `TampState.active` takes precedence and this
/// is never consulted. The scan runs in-process via libproc (callable straight
/// from Swift): the front-ends poll this while idle, and spawning a `pgrep`
/// subprocess every few seconds is needless fork/exec churn.
public enum SystemAssertions {
    /// Name of the live process with the given PID, or nil if it's gone.
    static func processName(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// A best-effort snapshot of every live PID on the system.
    static func allPIDs() -> [pid_t] {
        // proc_listallpids returns the number of PIDs (estimate when the
        // buffer is nil, entries written when it's provided).
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64) // headroom for new arrivals
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).filter { $0 > 0 }
    }

    public static func isCaffeinated() -> Bool {
        allPIDs().contains { processName(of: $0) == "caffeinate" }
    }
}
