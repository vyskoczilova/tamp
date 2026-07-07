import Foundation

/// Resolves a user-supplied target ("Xcode", "1234") to a live process for
/// `caffeinate -w`. Names match `proc_name` exactly (case-insensitively) —
/// predictable beats clever, and it keeps "Foo Helper" out of a match for
/// "Foo". Note that `proc_name` truncates names at 32 bytes.
public enum ProcessResolver {
    public enum ResolveError: Error, Equatable, CustomStringConvertible {
        case noSuchPID(pid_t)
        case noMatch(String)
        case ambiguous(String, pids: [pid_t])

        public var description: String {
            switch self {
            case .noSuchPID(let pid):
                return "No process with PID \(pid) is running."
            case .noMatch(let name):
                return "No running process is named \"\(name)\". "
                    + "If it is running, try its PID instead (names are matched "
                    + "exactly and the system truncates long ones)."
            case .ambiguous(let name, let pids):
                let list = pids.map(String.init).joined(separator: ", ")
                return "Several processes are named \"\(name)\" (PIDs \(list)). Re-run with a PID."
            }
        }
    }

    /// Resolve a process name or a numeric PID to a live (pid, name) pair.
    public static func resolve(_ target: String) throws -> (pid: pid_t, name: String) {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        if let pid = pid_t(trimmed) {
            guard let name = SystemAssertions.processName(of: pid) else {
                throw ResolveError.noSuchPID(pid)
            }
            return (pid, name)
        }
        let matches = SystemAssertions.allPIDs().compactMap { pid -> (pid: pid_t, name: String)? in
            guard let name = SystemAssertions.processName(of: pid),
                  name.caseInsensitiveCompare(trimmed) == .orderedSame
            else { return nil }
            return (pid, name)
        }
        switch matches.count {
        case 0: throw ResolveError.noMatch(trimmed)
        case 1: return matches[0]
        default: throw ResolveError.ambiguous(trimmed, pids: matches.map(\.pid).sorted())
        }
    }
}
