# ADR 001 — System-aware caffeinate detection

**Status:** Accepted  
**Date:** 2026-06-15

## Context

Coffee tracks only the `caffeinate` process it spawns itself (PID recorded in
`~/Library/Application Support/Coffee/state.json`). External tools that also
run `caffeinate` — such as the Claude Code hooks that call `caffeinate -is` on
every user prompt — are invisible to Coffee: the menu bar icon stays hollow and
`coffee status` says "Off" even while the Mac is actually kept awake.

The Raycast Coffee extension had the same design (it only tracked its own
process) but the conflict didn't arise there because Raycast was the only thing
managing caffeinate. The same assumption breaks once an external tool like Claude
Code enters the picture.

## Decision

Coffee reads the **live process list** via `pgrep -x caffeinate` whenever its own
state is **inactive**. If any `caffeinate` process is found, it reports
`CoffeeState.Phase.externallyActive` rather than `.off`. The icon shows the
active symbol and the status line says "On — caffeinated by another app".

This check is deliberately **read-only and passive**:

- Coffee never touches externally-started `caffeinate` processes.
- `coffee off` only kills Coffee's own tracked PID (unchanged).
- The "Keep Awake" toggle in the menu still starts Coffee's own session
  alongside any external one; they coexist harmlessly.

## Alternatives considered

**IOKit `IOPMCopyAssertionsByType`** — the canonical macOS API for querying
power assertions by type. More precise (checks the assertion, not just the
process name) but `IOPMCopyAssertionsByType` is not bridged in Swift's IOKit
module without a C shim, which adds build complexity for a single-function use.

**Running `pmset -g assertions`** — also reliable; parses text output. Similar
subprocess cost to `pgrep` but more fragile (text parsing).

**Routing external tools through Coffee's CLI** — have the Claude Code hooks call
`coffee on/off` instead of `caffeinate` directly. This makes Coffee the single
caffeinate owner but couples the hooks to Coffee's install path and semantics.
Rejected: Coffee should be passive here; the hook design belongs to the user's
Claude Code config.

## Consequences

- The status line can report "caffeinated by another app" in states where Coffee
  has no active session and therefore cannot offer a "time remaining" figure.
- The menu's "Keep Awake" toggle is disabled when `externallyActive` (Coffee
  can't turn off an external process, and the user would likely not expect it to).
- ~~`pgrep` is a subprocess call — cheap but not zero cost. It runs at most once
  per menu open and once per file-watcher event, never in a tight loop.~~
  *(Superseded — see Addendum.)*
- If a future need arises for finer-grained assertion introspection (e.g.
  identifying *which* app is caffeinating), IOKit via a C target in Package.swift
  is the right next step.

## Addendum (2026-07-06) — pgrep replaced by libproc

The menu bar app polls this check every 5 s while inactive, so the subprocess
cost was ~17k fork/execs a day. `proc_listallpids` + `proc_name` turned out to
be callable from plain Swift (`import Darwin`) — the "needs a C shim" concern
that originally favored `pgrep` applied to IOKit's assertion APIs, not to
libproc. `SystemAssertions.isCaffeinated()` now scans the process list
in-process; the decision itself (passive, name-based, read-only detection) is
unchanged.
