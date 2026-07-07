# Tamp — project guide

A macOS keep-awake tool (formerly "Coffee"). It wraps the built-in
`/usr/bin/caffeinate`, monitors both its own sessions and keep-awake processes
started by other apps, and ships **two products** over one shared engine:

- **`tamp`** — terminal CLI
- **`TampBar`** — menu bar app (runs as a background `.accessory`, no Dock icon)

Both talk to the same engine and the same on-disk state, so changing state in one
is reflected in the other.

## Build / test / run

```sh
swift build                 # debug build of all products
swift build -c release      # release build → .build/release/{tamp,TampBar}
swift run TampKitChecks     # run the test harness (exits non-zero on failure)
.build/debug/tamp status    # run the CLI
.build/debug/TampBar &      # run the menu bar app (bare binary — dev only)
Scripts/make-app.sh         # package build/Tamp.app (ad-hoc signed bundle)
Scripts/make-release.sh     # build universal zip + publish to the Homebrew tap
Scripts/uninstall.sh        # remove the app, login item, state, and prefs
```

**App bundle:** `Scripts/make-app.sh` assembles `build/Tamp.app` (writes the
`Info.plist` with `LSUIElement`, bundle id `cz.kybernaut.tamp`, ad-hoc signs).
Launch-at-login (`SMAppService`, see `LoginItem.swift`) only works from this
bundle — the bare binary disables that menu toggle. `build/` is gitignored.

**Bundle identity:** the SwiftPM target is `TampBar`, but `make-app.sh`
installs the binary into the bundle as `Contents/MacOS/Tamp` (and sets
`CFBundleExecutable=Tamp`) so the running process and the bundle share one
"Tamp" identity in the "Allow in the Menu Bar" list. The target itself can't
be renamed to `Tamp` — the filesystem is case-insensitive and would collide
with the `tamp` CLI. Avoid running the bare `.build/*/TampBar` binaries
except for quick dev checks: each distinct path you launch seeds its own stale
menu-bar entry that macOS won't auto-remove.

**Uninstall:** `Scripts/uninstall.sh` stops the tracked caffeinate, unregisters
the login item (via `Tamp --unregister-login`, a headless teardown hook in
`main.swift` that must run from inside the bundle so `SMAppService.mainApp`
resolves correctly), then deletes the app, state dir, and the prefs suite. It
also cleans up pre-rename "Coffee" installs.

**Tests:** there is no XCTest / Swift Testing target — this machine has Command
Line Tools only (no full Xcode), so neither framework is importable. Tests live in
`Sources/TampKitChecks/main.swift` as a plain executable assertion harness. Add
new checks there and run `swift run TampKitChecks`.

**Verifying real behavior (not just that it compiles):** keep-awake is a side
effect, so confirm it with the system, not the exit code:

```sh
tamp on  && pmset -g assertions | grep -E 'PreventUserIdleSystemSleep|PreventUserIdleDisplaySleep'
tamp off && pgrep -l caffeinate    # our tracked PID should be gone
```

Note: other apps may run their own `caffeinate` processes — only kill/track the
PID stored in our state file, never all `caffeinate` processes. A recorded PID
is only trusted/killed if it still names a caffeinate process (PIDs are
recycled — see `CaffeinateController.isTrackedCaffeinate`).

## Architecture

```
Sources/
├── TampKit/          shared engine library (the only place with real logic)
│   ├── CaffeinateController.swift  spawn/kill tracked caffeinate; reconcile state
│   ├── TampState.swift             Codable state model (active/pid/endsAt/flags) + Phase + StatusReport
│   ├── SystemAssertions.swift      libproc-based check for external caffeinate processes
│   ├── StateStore.swift            read/write the shared state JSON (NSFileCoordinator)
│   ├── Preferences.swift           sleep-type prefs + icon style (UserDefaults suite)
│   ├── Duration.swift              parse "1h30m"/"90s"/bare-minutes and "until HH:MM" (7-day cap)
│   ├── IconStyle.swift             icon styles incl. brewing concepts → SF Symbol names
│   └── Logging.swift               os.Logger for engine-level failures
├── tamp/             CLI (ArgumentParser) — thin wrapper over TampKit
├── TampBar/          menu bar app (AppKit NSStatusItem) — thin wrapper over TampKit
│   ├── main.swift          NSApplication bootstrap (.accessory policy)
│   ├── AppDelegate.swift   @MainActor status item, menu, state-file watcher
│   └── LoginItem.swift     SMAppService launch-at-login (needs the .app bundle)
└── TampKitChecks/    executable test harness for TampKit
```

**Golden rule: behavior lives in `TampKit`.** The CLI and the menu bar app are
both thin shells — when adding a feature, put the logic in `TampKit` and expose
it from both front-ends so they never drift.

### How the two products stay in sync

- Shared state file: `~/Library/Application Support/Tamp/state.json`
  (`{ active, pid, endsAt, flags }`).
- Shared preferences: `UserDefaults(suiteName: "cz.kybernaut.tamp")`.
- Whoever acts spawns a detached `caffeinate` and records its PID; stopping kills
  exactly that PID — after verifying it still names a caffeinate (PID reuse).
  `TampBar` watches the state file via `DispatchSource` and refreshes its icon
  when the CLI changes state (the CLI `icon` command re-saves state as a poke
  so style changes propagate too).
- `CaffeinateController.status()` reconciles: if the recorded PID is no longer
  a live caffeinate (timer elapsed, manual kill, or PID recycled), state is
  corrected to inactive.
- When Tamp's own state is inactive, `SystemAssertions.isCaffeinated()` scans
  the process list in-process via libproc (`proc_listallpids`/`proc_name` —
  callable from plain Swift, no C shim); if a caffeinate is alive,
  `TampState.Phase.externallyActive` is returned so both front-ends can display
  "caffeinated by another app". Tamp never kills or manages external processes.
  **Icon rule:** filled = any caffeinate active (`.onIndefinite`, `.onTimed`,
  `.externallyActive`); outline = nothing running (`.off` only). Custom-art styles
  ship an outline (inactive) + filled (active) SVG pair, so the rule holds for
  them too — `IconStyle.customAsset(active:)` returns the right one.
- `tamp status --json` emits a `StatusReport` envelope (state + resolved phase +
  remainingSeconds) so scripts see external caffeination too.

### Sleep flags → `caffeinate`

`SleepFlags` maps to `caffeinate` arguments: `-d` display, `-i` idle system,
`-m` disk, `-s` system-on-AC-only, `-u` declare-user-activity (wakes the
display; caffeinate holds it for the whole session only when timed);
`-t <seconds>` is added for timed sessions. Defaults: display + system on,
disk/AC-power/wake off. A session never launches a no-op `caffeinate` (falls
back to `-i`). New `SleepFlags` fields need `decodeIfPresent` defaults in
`init(from:)` so pre-existing `state.json` files keep decoding.
Durations are capped at 7 days (`DurationParser.maxSeconds`) — the cap check
doubles as the integer-overflow guard.

## Conventions

- Swift 6 language mode; top-level executable code is MainActor-isolated.
- Version bumps: update both `VERSION` (read by `Scripts/make-app.sh`) and
  `Sources/TampKit/Version.swift` (compiled into the binary, shown in the
  Settings footer). Convention: bump the patch on every meaningful code change.
- New icon styles: add a case to `IconStyle` and map active/inactive SF Symbol
  names in both `inactiveSymbol` and `activeSymbol`. To check whether a symbol
  name exists on this machine:
  `swift -e 'import AppKit; print(NSImage(systemSymbolName: "name", accessibilityDescription: nil) != nil)'`
  Custom-art styles instead drop an outline + filled SVG pair into
  `Sources/TampBar/Icons/` and point `IconStyle.customAsset(active:)` at the
  basenames. `IconRenderer` (TampBar) loads the state-appropriate one via
  `Bundle.module` as a template image (rendered icons are cached per
  style/state/size); `make-app.sh` copies the generated `Tamp_TampBar.bundle`
  into the app. Cases are ordered alphabetically by `label`; the default style
  (when no pref is set) is `Preferences.iconStyle`'s getter fallback.
- Previewing icon artwork: `swift Scripts/icon-preview.swift [svg-dir] [out.png]`
  renders a contact sheet (each icon at 18px + 44px, on a light and a dark bar)
  so you can judge legibility before wiring SVGs in. Defaults to the `Icons/`
  dir → `build/icon-preview.png`; pass a candidate folder (e.g. `tmp`) to vet new
  art. `open` the PNG to view. This is the canonical preview path — don't hand-roll
  throwaway render scripts.
- Keep `tamp` and `TampBar` symmetric: any capability one exposes, the other
  should be able to reach through `TampKit`.

## Distribution (Homebrew)

- Public tap: `vyskoczilova/homebrew-tap` (`Formula/tamp.rb`) — the source repo
  is private, so the formula installs **prebuilt binaries** from zips attached
  to the tap repo's GitHub Releases. Formula downloads don't get the Gatekeeper
  quarantine attribute, so ad-hoc signing is fine through this path.
- `Scripts/make-release.sh` builds the universal zip, uploads the release, and
  bumps the formula.
- Upgrade path: Developer ID + notarization → proper cask (`Casks/tamp.rb`),
  one-step /Applications install.

## Roadmap (v2, not yet built)

- `caffeinate -w <pid>` ("keep awake while app X runs")
- Session extend, end-time display, end-of-session notification
- Natural-language recurring schedules

Done since v1.0.0: rename Coffee → Tamp; PID-identity safety; 7-day duration
cap; libproc detection; icon render cache; JSON phase report; MIT license;
Homebrew tap distribution; `-s`/`-u` flags (CLI `--ac`/`--wake`, settings
toggles, v1.1.0).

## License

MIT (see `LICENSE`). Original implementation, inspired by the MIT-licensed
Raycast Coffee extension — no code or artwork copied; only Apple's `caffeinate`
is wrapped. Icon artwork from the Noun Project, CC BY 3.0
(`Sources/TampBar/Icons/CREDITS.txt`).
