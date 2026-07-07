## Features

[ ] "While app runs" — tamp while Xcode — keeps Mac awake as long as a named
    app is open (uses caffeinate -w <pid>). Useful for builds, video calls, etc.

[ ] Shell completions + man page in the Homebrew formula
    (ArgumentParser: `tamp --generate-completion-script zsh`).

[ ] "Which app is caffeinating?" — IOKit assertion introspection
    (IOPMCopyAssertionsByProcess) to name the external culprit.

[ ] Recurring schedules — "keep awake weekdays 9–17" — needs a scheduler layer.

## Distribution

[ ] Developer ID signing + notarization → Homebrew cask (one-step
    /Applications install; personal-tap formula works fine meanwhile).

## Done

[x] Session extend — `tamp add 15m` + Extend submenu (timed sessions only,
    7-day cap re-checked); end time shown in menu/CLI ("1h 7m left (until
    17:30)"); opt-in end-of-session notification posted by TampBar via a
    pending UNNotification keyed to endsAt (works for CLI-started sessions
    too; needs the packaged app) (v1.2.0)
[x] Expose remaining caffeinate flags: -s (AC power) and -u (wake display) —
    CLI --ac/--wake overrides + settings toggles; legacy state.json still
    decodes (v1.1.0)
[x] CLI: on / off / toggle / for / until / status / icon
[x] Menu bar app with file watcher (CLI changes reflect immediately)
[x] Timed sessions (caffeinate -t), indefinite sessions
[x] Sleep-flag prefs (display/system/disk) shared between CLI and app
[x] Icon styles including brewing concepts (custom SVG template art)
[x] App bundle + launch-at-login (SMAppService)
[x] External caffeinate detection — icon shows active when another app caffeinated
[x] Custom… duration input in Keep Awake For submenu
[x] Settings panel (NSPanel) — sleep flags, icon style, launch-at-login
[x] v1.0.0 review fixes: PID-identity before kill/reconcile; 7-day duration cap
    (overflow-proof); libproc instead of pgrep polling; icon render cache;
    status --json phase report; CLI icon-change poke; state-store error logging
[x] Rename Coffee → Tamp; MIT license
[x] Homebrew: public tap with prebuilt-binary formula (private source repo)
