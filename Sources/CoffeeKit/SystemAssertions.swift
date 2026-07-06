import Foundation

/// Checks whether any caffeinate process is alive on the system, regardless
/// of who started it. Used only when Coffee's own state is inactive — if
/// Coffee has a live session, `CoffeeState.active` takes precedence and this
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

    public static func isCaffeinated() -> Bool {
        // proc_listallpids returns the number of PIDs (estimate when the
        // buffer is nil, entries written when it's provided).
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64) // headroom for new arrivals
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return false }
        return pids.prefix(Int(filled)).contains { $0 > 0 && processName(of: $0) == "caffeinate" }
    }
}
