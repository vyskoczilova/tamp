import Foundation

/// Checks whether any caffeinate process is alive on the system, regardless
/// of who started it. Used only when Coffee's own state is inactive — if
/// Coffee has a live session, `CoffeeState.active` takes precedence and this
/// is never consulted. The pgrep exit code (0 = found) is the check; we need
/// no output.
public enum SystemAssertions {
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
