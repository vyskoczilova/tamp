# Coffee

Keep your Mac awake — a small, Raycast-free menu bar app plus a terminal CLI,
both built around macOS's built-in `caffeinate`.

## What it does

- **Toggle** keep-awake on/off
- **Caffeinate for** a duration (`30m`, `1h`, `1h30m`, `90s`) or **until** a clock time (`17:30`)
- Independently prevent **display / system / disk** sleep
- A menu bar icon that reflects the current state, with a selectable icon style
  including coffee **brewing concepts** (pour-over, espresso, French press, kettle)
- A `coffee` CLI and the menu bar app share one source of truth, so changing
  state in one is reflected in the other

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

# Run the menu bar app (consider adding to Login Items)
.build/release/CoffeeBar &
```

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

## Tests

```sh
swift run CoffeeKitChecks
```

(A plain executable harness — the standard test frameworks require full Xcode,
which this setup doesn't have.)

## Roadmap (v2)

- "Caffeinate while app X runs" (`caffeinate -w <pid>`)
- Natural-language recurring schedules
- Launch-at-login via `SMAppService` and a notarized `.app` bundle
- Custom template artwork for the brewing-concept icon styles (they currently
  fall back to SF Symbols)

## License & attribution

Original implementation. Behavior was inspired by the MIT-licensed Raycast
"Coffee" extension, but no code or artwork was copied — only the public
behavior of Apple's `caffeinate` is wrapped. Choose your own license before
distributing.
