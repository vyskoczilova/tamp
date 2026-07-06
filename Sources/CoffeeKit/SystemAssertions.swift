import Foundation

/// Checks whether any caffeinate process is alive on the system, regardless
/// of who started it. Used only when Coffee's own state is inactive — if
/// Coffee has a live session, `CoffeeState.active` takes precedence and this
/// is never consulted. The pgrep exit code (0 = found) is the check; we need
/// no output.
public enum SystemAssertions {
    /// Name of the live process with the given PID, or nil if it's gone.
    /// libproc is callable straight from Swift, no C shim needed.
    static func processName(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 64)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    public static func isCaffeinated() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "caffeinate"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
