import ArgumentParser
import TampKit
import Foundation

@main
struct Tamp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tamp",
        abstract: """
        Keep your Mac awake. Karolína Vyskočilová's wrapper around the native \
        macOS caffeinate command — tracks its own sessions and shows when other \
        apps keep the Mac awake. Inspired by the Raycast Coffee extension.
        """,
        discussion: "Project & release notes: \(appRepoURL.absoluteString)",
        version: appVersion,
        subcommands: [
            On.self, Off.self, Toggle.self, For.self, Until.self,
            Hold.self, Release.self, Status.self, Icon.self,
        ],
        defaultSubcommand: Status.self
    )
}

/// Flags shared by commands that start a session, letting a single run override
/// the saved sleep preferences.
struct SleepOverrides: ParsableArguments {
    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the display from sleeping.")
    var display: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the system from idle sleeping.")
    var system: Bool?

    @Flag(name: .long, inversion: .prefixedNo, help: "Prevent the disk from idle sleeping.")
    var disk: Bool?

    /// Returns flags only if the user overrode at least one; otherwise nil so
    /// the engine falls back to saved preferences.
    func resolved() -> SleepFlags? {
        guard display != nil || system != nil || disk != nil else { return nil }
        let base = Preferences().sleepFlags
        return SleepFlags(
            display: display ?? base.display,
            system: system ?? base.system,
            disk: disk ?? base.disk
        )
    }
}

struct On: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Keep awake indefinitely.")
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let state = try CaffeinateController().start(flags: overrides.resolved())
        print(describe(state))
    }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Allow sleep again.")
    func run() throws {
        let state = CaffeinateController().stop()
        print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
    }
}

struct Toggle: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Toggle keep-awake on/off.")
    func run() throws {
        let state = try CaffeinateController().toggle()
        print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
    }
}

struct For: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "for",
        abstract: "Keep awake for a duration, e.g. 'tamp for 2h' or '1h30m'."
    )
    @Argument(help: "Duration: 30m, 1h, 1h30m, 90s (bare number = minutes).")
    var duration: String
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let seconds = try DurationParser.seconds(from: duration)
        let state = try CaffeinateController().start(duration: seconds, flags: overrides.resolved())
        print(describe(state))
    }
}

struct Until: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep awake until a clock time, e.g. 'tamp until 17:30'."
    )
    @Argument(help: "Time in 24h HH:MM. Past times roll to tomorrow.")
    var time: String
    @OptionGroup var overrides: SleepOverrides

    func run() throws {
        let seconds = try DurationParser.secondsUntil(time: time)
        let state = try CaffeinateController().start(duration: seconds, flags: overrides.resolved())
        print(describe(state))
    }
}

struct Hold: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Register a named hold that keeps the Mac awake (refcounted).",
        discussion: """
        Holds let any number of concurrent scripts share keep-awake safely: the \
        first hold starts caffeinate, further holds just add their id, and it \
        stops only when the last hold is released (and no manual session is \
        active). Re-holding the same id refreshes it. 'tamp off' force-stops \
        everything, holds included.
        """
    )
    @Argument(help: "Hold identifier, e.g. a session or job id.")
    var id: String

    @Option(name: .customLong("for"), help: ArgumentHelp(
        "Auto-release after a duration (30m, 4h…), so a crashed caller can't pin the Mac awake. Re-holding refreshes it.",
        valueName: "duration"
    ))
    var duration: String?

    func run() throws {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError("Hold id must not be empty.") }
        let ttl = try duration.map { try DurationParser.seconds(from: $0) }
        let state = try CaffeinateController().hold(trimmed, ttl: ttl)
        print(describe(state))
    }
}

struct Release: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Release a named hold; keep-awake stops when the last one goes."
    )
    @Argument(help: "Hold identifier passed to 'tamp hold'. Unknown ids are a no-op.")
    var id: String?

    @Flag(name: .long, help: "Release all holds (a manual session keeps running).")
    var all = false

    func run() throws {
        let controller = CaffeinateController()
        let state: TampState
        if all {
            state = controller.releaseAll()
        } else if let id {
            state = try controller.release(id.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            throw ValidationError("Provide a hold id or --all.")
        }
        print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show current state.")
    @Flag(name: .long, help: "Output machine-readable JSON.")
    var json = false

    func run() throws {
        let state = CaffeinateController().status()
        if json {
            let report = StatusReport(state: state, systemActive: SystemAssertions.isCaffeinated())
            let data = try JSONEncoder.tamp.encode(report)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print(describe(state, systemActive: SystemAssertions.isCaffeinated()))
            let holders = state.liveHolders()
            if !holders.isEmpty {
                print("   holds: \(holders.map(\.id).joined(separator: ", "))")
            }
        }
    }
}

struct Icon: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Get or set the menu bar icon style."
    )
    @Argument(help: "Style to set. Omit to list available styles and the current one.")
    var style: String?

    func run() throws {
        let prefs = Preferences()
        guard let style else {
            for s in IconStyle.allCases {
                let marker = s == prefs.iconStyle ? "*" : " "
                print("\(marker) \(s.rawValue) — \(s.label)")
            }
            return
        }
        guard let chosen = IconStyle(rawValue: style) else {
            let names = IconStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown style \"\(style)\". Choose one of: \(names).")
        }
        prefs.iconStyle = chosen
        // Poke the shared state file so a running menu bar app notices the new
        // style immediately — it watches the file, not UserDefaults, and an
        // indefinite session has no poll timer to pick the change up otherwise.
        // A no-op mutate re-saves atomically without the load-then-save race
        // that could clobber a concurrent hold/release.
        StateStore().mutate { _ in }
        print("Icon style set to \(chosen.label).")
    }
}

/// Render a state as a one-line human summary. `systemActive` is an
/// autoclosure so the full process-table scan behind it only runs when the
/// phase actually depends on it (state neither active nor held).
func describe(_ state: TampState, systemActive: @autoclosure () -> Bool = false) -> String {
    switch state.phase(systemActive: systemActive()) {
    case .off:
        return "☕️ Off — your Mac can sleep normally."
    case .onTimed(let remaining):
        return "☕️ On — \(DurationParser.format(remaining: remaining)) left."
    case .onIndefinite:
        return "☕️ On — staying awake until turned off."
    case .heldBy(let count):
        return "☕️ On — \(TampState.Holder.countLabel(count))."
    case .externallyActive:
        return "☕️ On — caffeinated by another app."
    }
}
