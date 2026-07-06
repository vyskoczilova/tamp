# Tamp

Keep your Mac awake — a small, Raycast-free menu bar app plus a terminal CLI,
both built around macOS's built-in `caffeinate`. Named after the coffee tamper
(and the menu bar icon that goes with it).

## What it does

- **Toggle** keep-awake on/off
- **Caffeinate for** a duration (`30m`, `1h`, `1h30m`, `90s`; capped at 7 days)
  or **until** a clock time (`17:30`)
- Independently prevent **display / system / disk** sleep
- A menu bar icon that reflects the current state, with a selectable icon style
  including coffee **brewing concepts** (tamper, pour-over, filter, pot)
- A `tamp` CLI and the menu bar app share one source of truth, so changing
  state in one is reflected in the other
- The icon and status also reflect **external caffeination** — if another tool
  (e.g. Claude Code hooks) is keeping the Mac awake, Tamp shows it

## Install (Homebrew)

```sh
brew install vyskoczilova/tap/tamp
```

Then copy the menu bar app to /Applications (see the formula caveats):

```sh
cp -R "$(brew --prefix tamp)/Tamp.app" /Applications/
open /Applications/Tamp.app
```

## Build from source

Requires the Swift toolchain (Swift 6+). No Xcode needed.

```sh
swift build -c release
```

Binaries land in `.build/release/`:

- `tamp` — the CLI
- `TampBar` — the menu bar app (runs as a background "accessory", no Dock icon)

Package the menu bar app as a real `Tamp.app` bundle (ad-hoc signed, no Dock
icon) and run it like any other app:

```sh
Scripts/make-app.sh --install   # builds build/Tamp.app, installs to /Applications, launches
```

A coffee-tamper icon appears in the menu bar. To start it automatically at
login, click the icon → **Settings…** → **Launch at Login** (uses
`SMAppService`; the app must live in `/Applications`).

You can also run the bare binary without bundling — `.build/release/TampBar &` —
but then the "Launch at Login" toggle is disabled (it needs a real `.app`).

## CLI usage

```sh
tamp on              # keep awake until turned off
tamp off             # allow sleep again
tamp toggle          # flip current state
tamp for 2h          # keep awake for 2 hours
tamp until 17:30     # keep awake until 17:30 (rolls to tomorrow if past)
tamp status          # show state ( --json for scripting, incl. resolved phase )
tamp icon            # list icon styles ( * marks current )
tamp icon pourOver   # set the menu bar icon style

# Per-run sleep overrides (otherwise saved preferences apply):
tamp on --no-display --system
```

## How it works

Each session shells out to `/usr/bin/caffeinate` with flags mapped from your
preferences (`-d` display, `-i` idle system, `-m` disk) and `-t <seconds>` for
timed sessions. The running PID and session details are persisted to
`~/Library/Application Support/Tamp/state.json`; the menu bar app watches that
file so CLI changes show up immediately. If a tracked process dies (timer
elapsed or manual kill), the state self-reconciles to "off" — and a recorded
PID is never trusted (or killed) unless it still names a caffeinate process,
so recycled PIDs are harmless.

When Tamp's own state is inactive, it also checks the live process list (via
libproc, in-process) for any external caffeinate keeping the Mac awake. If one
exists, the icon and status line show "On — caffeinated by another app" —
read-only, Tamp never touches external processes. See
`docs/adr/001-system-aware-caffeinate-detection.md`.

## Tests

```sh
swift run TampKitChecks
```

(A plain executable harness — the standard test frameworks require full Xcode,
which this setup doesn't have.)

## Uninstall

```sh
Scripts/uninstall.sh   # stops the session, unregisters login item, removes app/state/prefs
```

## Roadmap (v2)

- "Caffeinate while app X runs" (`caffeinate -w <pid>`)
- Expose `caffeinate -s` (keep awake on AC power) and `-u` (declare user activity)
- Session extend ("+15 m"), end-time display, end-of-session notification
- Natural-language recurring schedules
- Distribution upgrade: Developer ID signing + notarization → Homebrew cask

## License & attribution

MIT — see `LICENSE`. Original implementation; behavior was inspired by the
MIT-licensed Raycast "Coffee" extension, but no code or artwork was copied —
only the public behavior of Apple's `caffeinate` is wrapped. Icon artwork from
the Noun Project (see `Sources/TampBar/Icons/CREDITS.txt`).
