# Coffee

Keep your Mac awake — a small, Raycast-free menu bar app plus a terminal CLI,
both built around macOS's built-in `caffeinate`.

## What it does

- **Toggle** keep-awake on/off
- **Caffeinate for** a duration (`30m`, `1h`, `1h30m`, `90s`) or **until** a clock time (`17:30`)
- Independently prevent **display / system / disk** sleep
- A menu bar icon that reflects the current state, with a selectable icon style
  including coffee **brewing concepts** (pour-over, filter, pot, tamper)
- A `coffee` CLI and the menu bar app share one source of truth, so changing
  state in one is reflected in the other
- The icon and status also reflect **external caffeination** — if another tool
  (e.g. Claude Code hooks) is keeping the Mac awake, Coffee shows it

## Build

Requires the Swift toolchain (Swift 6+). No Xcode needed.

```sh
swift build -c release
```

Binaries land in `.build/release/`:

- `coffee` — the CLI
- `CoffeeBar` — the menu bar app (runs as a background "accessory", no Dock icon)

### Install (personal use)

```sh
# CLI on your PATH
cp .build/release/coffee /usr/local/bin/coffee
```

### Menu bar app

Package the menu bar app as a real `Coffee.app` bundle (ad-hoc signed, no Dock
icon) and run it like any other app:

```sh
Scripts/make-app.sh           # builds build/Coffee.app
mv build/Coffee.app /Applications/
open /Applications/Coffee.app
```

A coffee-cup icon appears in the menu bar. To start it automatically at login,
click the icon → **Launch at Login** (uses `SMAppService`; move the app to
`/Applications` first so the registration points at a stable path).

You can also run the bare binary without bundling — `\.build/release/CoffeeBar &` —
but then the "Launch at Login" toggle is disabled (it needs a real `.app`).

## CLI usage

```sh
coffee on              # keep awake until turned off
coffee off             # allow sleep again
coffee toggle          # flip current state
coffee for 2h          # keep awake for 2 hours
coffee until 17:30     # keep awake until 17:30 (rolls to tomorrow if past)
coffee status          # show state ( --json for scripting )
coffee icon            # list icon styles ( * marks current )
coffee icon pourOver   # set the menu bar icon style

# Per-run sleep overrides (otherwise saved preferences apply):
coffee on --no-display --system
```

## How it works

Each session shells out to `/usr/bin/caffeinate` with flags mapped from your
preferences (`-d` display, `-i` idle system, `-m` disk) and `-t <seconds>` for
timed sessions. The running PID and session details are persisted to
`~/Library/Application Support/Coffee/state.json`; the menu bar app watches that
file so CLI changes show up immediately. If a tracked process dies (timer
elapsed or manual kill), the state self-reconciles to "off".

When Coffee's own state is inactive, it also checks (`pgrep -x caffeinate`)
whether any external process is caffeinating the Mac. If so, the icon and status
line show "On — caffeinated by another app" — read-only, Coffee never touches
external processes. See `docs/adr/001-system-aware-caffeinate-detection.md`.

## Tests

```sh
swift run CoffeeKitChecks
```

(A plain executable harness — the standard test frameworks require full Xcode,
which this setup doesn't have.)

## Roadmap (v2)

- "Caffeinate while app X runs" (`caffeinate -w <pid>`)
- Natural-language recurring schedules
- Distribution: Developer ID signing + notarization (the bundle is ad-hoc
  signed today, which is fine for personal use) and a Homebrew cask

Done since v1.0.0: a real `Coffee.app` bundle (`Scripts/make-app.sh`),
launch-at-login via `SMAppService`, and custom template artwork for the
brewing-concept icon styles (bundled SVG pairs via `IconRenderer`).

## License & attribution

Original implementation. Behavior was inspired by the MIT-licensed Raycast
"Coffee" extension, but no code or artwork was copied — only the public
behavior of Apple's `caffeinate` is wrapped. Choose your own license before
distributing.
