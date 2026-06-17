# Coffee — project guide

A Raycast-free macOS keep-awake tool. It wraps the built-in `/usr/bin/caffeinate`
and ships **two products** over one shared engine:

- **`coffee`** — terminal CLI
- **`CoffeeBar`** — menu bar app (runs as a background `.accessory`, no Dock icon)

Both talk to the same engine and the same on-disk state, so changing state in one
is reflected in the other.

## Build / test / run

```sh
swift build                 # debug build of all products
swift build -c release      # release build → .build/release/{coffee,CoffeeBar}
swift run CoffeeKitChecks   # run the test harness (exits non-zero on failure)
.build/debug/coffee status  # run the CLI
.build/debug/CoffeeBar &    # run the menu bar app (bare binary — dev only)
Scripts/make-app.sh         # package build/Coffee.app (ad-hoc signed bundle)
Scripts/uninstall.sh        # remove the app, login item, state, and prefs
```

**App bundle:** `Scripts/make-app.sh` assembles `build/Coffee.app` (writes the
`Info.plist` with `LSUIElement`, bundle id `cz.kybernaut.coffee`, ad-hoc signs).
Launch-at-login (`SMAppService`, see `LoginItem.swift`) only works from this
bundle — the bare binary disables that menu toggle. `build/` is gitignored.

**Bundle identity:** the SwiftPM target is `CoffeeBar`, but `make-app.sh`
installs the binary into the bundle as `Contents/MacOS/Coffee` (and sets
`CFBundleExecutable=Coffee`) so the running process and the bundle share one
"Coffee" identity in the "Allow in the Menu Bar" list. The target itself can't
be renamed to `Coffee` — the filesystem is case-insensitive and would collide
with the `coffee` CLI. Avoid running the bare `.build/*/CoffeeBar` binaries
except for quick dev checks: each distinct path you launch seeds its own stale
menu-bar entry that macOS won't auto-remove.

**Uninstall:** `Scripts/uninstall.sh` stops the tracked caffeinate, unregisters
the login item (via `CoffeeBar --unregister-login`, a headless teardown hook in
`main.swift` that must run from inside the bundle so `SMAppService.mainApp`
resolves correctly), then deletes the app, state dir, and the prefs suite.

**Tests:** there is no XCTest / Swift Testing target — this machine has Command
Line Tools only (no full Xcode), so neither framework is importable. Tests live in
`Sources/CoffeeKitChecks/main.swift` as a plain executable assertion harness. Add
new checks there and run `swift run CoffeeKitChecks`.

**Verifying real behavior (not just that it compiles):** keep-awake is a side
effect, so confirm it with the system, not the exit code:

```sh
coffee on  && pmset -g assertions | grep -E 'PreventUserIdleSystemSleep|PreventUserIdleDisplaySleep'
coffee off && pgrep -l caffeinate    # our tracked PID should be gone
```

Note: other apps may run their own `caffeinate` processes — only kill/track the
PID stored in our state file, never all `caffeinate` processes.

## Architecture

```
Sources/
├── CoffeeKit/        shared engine library (the only place with real logic)
│   ├── CaffeinateController.swift  spawn/kill tracked caffeinate; reconcile state
│   ├── CoffeeState.swift           Codable state model (active/pid/endsAt/flags) + Phase enum
│   ├── SystemAssertions.swift      pgrep-based check for external caffeinate processes
│   ├── StateStore.swift            read/write the shared state JSON (NSFileCoordinator)
│   ├── Preferences.swift           sleep-type prefs + icon style (UserDefaults suite)
│   ├── Duration.swift              parse "1h30m"/"90s"/bare-minutes and "until HH:MM"
│   └── IconStyle.swift             icon styles incl. brewing concepts → SF Symbol names
├── coffee/           CLI (ArgumentParser) — thin wrapper over CoffeeKit
├── CoffeeBar/        menu bar app (AppKit NSStatusItem) — thin wrapper over CoffeeKit
│   ├── main.swift          NSApplication bootstrap (.accessory policy)
│   ├── AppDelegate.swift   @MainActor status item, menu, state-file watcher
│   └── LoginItem.swift     SMAppService launch-at-login (needs the .app bundle)
└── CoffeeKitChecks/  executable test harness for CoffeeKit
```

**Golden rule: behavior lives in `CoffeeKit`.** The CLI and the menu bar app are
both thin shells — when adding a feature, put the logic in `CoffeeKit` and expose
it from both front-ends so they never drift.

### How the two products stay in sync

- Shared state file: `~/Library/Application Support/Coffee/state.json`
  (`{ active, pid, endsAt, flags }`).
- Shared preferences: `UserDefaults(suiteName: "cz.kybernaut.coffee")`.
- Whoever acts spawns a detached `caffeinate` and records its PID; stopping kills
  exactly that PID. `CoffeeBar` watches the state file via `DispatchSource` and
  refreshes its icon when the CLI changes state.
- `CaffeinateController.status()` reconciles: if the recorded PID is no longer
  alive (timer elapsed or manual kill), state is corrected to inactive.
- When Coffee's own state is inactive, `SystemAssertions.isCaffeinated()` checks
  `pgrep -x caffeinate`; if alive, `CoffeeState.Phase.externallyActive` is
  returned so both front-ends can display "caffeinated by another app".
  Coffee never kills or manages external processes.
  **Icon rule:** filled = any caffeinate active (`.onIndefinite`, `.onTimed`,
  `.externallyActive`); outline = nothing running (`.off` only). Custom-art styles
  ship an outline (inactive) + filled (active) SVG pair, so the rule holds for
  them too — `IconStyle.customAsset(active:)` returns the right one.

### Sleep flags → `caffeinate`

`SleepFlags` maps to `caffeinate` arguments: `-d` display, `-i` idle system,
`-m` disk; `-t <seconds>` is added for timed sessions. Defaults: display + system
on, disk off. A session never launches a no-op `caffeinate` (falls back to `-i`).

## Conventions

- Swift 6 language mode; top-level executable code is MainActor-isolated.
- Version bumps: update both `VERSION` (read by `Scripts/make-app.sh`) and
  `Sources/CoffeeKit/Version.swift` (compiled into the binary, shown in menu).
  Convention: bump the patch on every meaningful code change.
- New icon styles: add a case to `IconStyle` and map active/inactive SF Symbol
  names in both `inactiveSymbol` and `activeSymbol`. To check whether a symbol
  name exists on this machine:
  `swift -e 'import AppKit; print(NSImage(systemSymbolName: "name", accessibilityDescription: nil) != nil)'`
  Custom-art styles instead drop an outline + filled SVG pair into
  `Sources/CoffeeBar/Icons/` and point `IconStyle.customAsset(active:)` at the
  basenames. `IconRenderer` (CoffeeBar) loads the state-appropriate one via
  `Bundle.module` as a template image; `make-app.sh` copies the generated
  `Coffee_CoffeeBar.bundle` into the app. Cases are ordered alphabetically by
  `label`; the default style (when no pref is set) is `Preferences.iconStyle`'s
  getter fallback.
- Previewing icon artwork: `swift Scripts/icon-preview.swift [svg-dir] [out.png]`
  renders a contact sheet (each icon at 18px + 44px, on a light and a dark bar)
  so you can judge legibility before wiring SVGs in. Defaults to the `Icons/`
  dir → `build/icon-preview.png`; pass a candidate folder (e.g. `tmp`) to vet new
  art. `open` the PNG to view. This is the canonical preview path — don't hand-roll
  throwaway render scripts.
- Keep `coffee` and `CoffeeBar` symmetric: any capability one exposes, the other
  should be able to reach through `CoffeeKit`.

## Roadmap (v2, not yet built)

- `caffeinate -w <pid>` ("keep awake while app X runs")
- Natural-language recurring schedules
- Custom artwork for the brewing-concept icon styles
- Distribution: Developer ID signing + notarization (the bundle is ad-hoc
  signed today, fine for personal use); Homebrew cask

Done since v1.0.0: `Coffee.app` bundle (`Scripts/make-app.sh`) and
launch-at-login via `SMAppService` (`LoginItem.swift`).

## License

Original implementation. Behavior inspired by the MIT-licensed Raycast Coffee
extension; no code or artwork copied (only Apple's `caffeinate` is wrapped).
Pick a license before distributing.
