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
│   ├── SystemAssertions.swift      libproc detection of external caffeinates + their launchers
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
- When Tamp's own state is inactive, `SystemAssertions.externalCaffeinations()`
  scans the process list in-process via libproc (`proc_listallpids`/`proc_name` —
  callable from plain Swift, no C shim) and resolves each match's launcher via
  `proc_pidinfo`/`PROC_PIDTBSDINFO` (parent PID + name; the parent lookup runs
  only for matching PIDs, so a no-caffeinate scan costs the same as before).
  Live matches ride in `TampState.Phase.externallyActive(sources:)` so both
  front-ends display "caffeinated by bash (pid 1234)" — the shared wording
  lives in `ExternalCaffeination.sourceDescription` / `.sourceSummary`. An
  orphaned caffeinate (parent exited → reparented to launchd) is reported as
  orphaned with its own PID, never attributed to launchd. Tamp never kills or
  manages external processes.
  **Icon rule:** filled = any caffeinate active (`.onIndefinite`, `.onTimed`,
  `.externallyActive`); outline = nothing running (`.off` only). Custom-art styles
  ship an outline (inactive) + filled (active) SVG pair, so the rule holds for
  them too — `IconStyle.customAsset(active:)` returns the right one.
- `tamp status --json` emits a `StatusReport` envelope (state + resolved phase +
  remainingSeconds + externalSources) so scripts see external caffeination —
  including who launched it — too.

### Sleep flags → `caffeinate`

`SleepFlags` maps to `caffeinate` arguments: `-d` display, `-i` idle system,
`-m` disk; `-t <seconds>` is added for timed sessions. Defaults: display + system
on, disk off. A session never launches a no-op `caffeinate` (falls back to `-i`).
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

## GitHub

- **Main repo:** [`vyskoczilova/tamp`](https://github.com/vyskoczilova/tamp) —
  public, issues enabled. `TampKit/Version.swift`'s `appRepoURL` is the
  in-app source of truth for this link (Settings footer, release-notes URL).
- **Homebrew tap:** [`vyskoczilova/homebrew-tap`](https://github.com/vyskoczilova/homebrew-tap)
  — holds only `Formula/tamp.rb`, no source code.
- **GitHub Pages site:** `docs/` on the `main` branch publishes to
  **https://tamp.kybernaut.cz** (custom domain via `docs/CNAME`) — the
  marketing/landing page, entirely separate from the Swift app. Edit
  `docs/index.html` / `docs/assets/` directly; pushes to `main` redeploy
  automatically (no build step, no Jekyll — see `docs/.nojekyll`).
- **ADRs:** significant design decisions are recorded in `docs/adr/` (e.g.
  `001-system-aware-caffeinate-detection.md`). Add a new ADR for decisions
  worth explaining to a future reader, not routine changes.
- **Issues vs `TODO.md`:** the feature backlog lives in `TODO.md` (checked
  into git); community-sourced ideas (e.g. from Reddit feedback) get filed as
  GitHub issues instead — the two can drift, so check both before roadmap work.

## Distribution (Homebrew)

- Public tap: `vyskoczilova/homebrew-tap` (`Formula/tamp.rb`) — the formula
  installs **prebuilt binaries** from zips attached to GitHub Releases on the
  main `vyskoczilova/tamp` repo (both repos are public — see GitHub section
  above). Formula downloads don't get the Gatekeeper quarantine attribute, so
  ad-hoc signing is fine through this path.
- `Scripts/make-release.sh` builds the universal zip, uploads the release, and
  bumps the formula.
- Upgrade path: Developer ID + notarization → proper cask (`Casks/tamp.rb`),
  one-step /Applications install.

## Roadmap

Tracked in `TODO.md` (Features / Distribution / Done) — edit that file
directly rather than this section so the two can't drift. Open GitHub issues
(e.g. #4) sometimes cover the same item with more implementation detail than
the one-liner in `TODO.md`.

## License

MIT (see `LICENSE`). Original implementation, inspired by the MIT-licensed
Raycast Coffee extension — no code or artwork copied; only Apple's `caffeinate`
is wrapped. Icon artwork from the Noun Project, CC BY 3.0
(`Sources/TampBar/Icons/CREDITS.txt`).
