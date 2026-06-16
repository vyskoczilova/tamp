## Think about

### Can you run both Homebrew Cask and App Store?

Yes, plenty of apps do (free direct/Homebrew build + paid App Store build). But for this app there's a sharp catch you need to know before you name anything:

The App Store requires sandboxing, and your current engine can't be sandboxed. Coffee works by spawning /usr/bin/caffeinate as a detached subprocess, recording its PID, and using pgrep to detect external caffeinate. A sandboxed app cannot spawnt arbitrary executables or run pgrep. So an App Store build would require rewriting CaffeinateController to use the IOKit power-assertion API (IOPMAssertionCreateWithName) instead of wrapping caffeinate. That's exactly how Amphetamine (the dominant free App Store competitor) does it.

## UX / menu

[ ] brewing-concept icon styles (pourOver, espresso, frenchPress, kettle) all
    fall back to cup.and.saucer SF Symbol — visually identical to "Cup".
    Fix: find distinct SF Symbols per style, or add custom template image assets.

## Features

[ ] "While app runs" — coffee while Xcode — keeps Mac awake as long as a named
    app is open (uses caffeinate -w <pid>). Useful for builds, video calls, etc.

[ ] Recurring schedules — "keep awake weekdays 9–17" — needs a scheduler layer.

## Distribution

[ ] Custom artwork for brewing-concept icon styles (currently SF Symbol fallbacks).
[ ] Developer ID signing + notarization (currently ad-hoc, fine for personal use).
[ ] Homebrew cask.

## Done

[x] CLI: on / off / toggle / for / until / status / icon
[x] Menu bar app with file watcher (CLI changes reflect immediately)
[x] Timed sessions (caffeinate -t), indefinite sessions
[x] Sleep-flag prefs (display/system/disk) shared between CLI and app
[x] Icon styles including brewing concepts (SF Symbol fallbacks for now)
[x] Coffee.app bundle + launch-at-login (SMAppService)
[x] External caffeinate detection — icon shows active when another app caffeinated
[x] Custom… duration input in Keep Awake For submenu
[x] Menu stays fully interactive even when external caffeinate is running
[x] Settings panel (NSPanel) — sleep flags, icon style, launch-at-login moved
    out of the menu
[x] About panel — system About box with version + copyright (NSHumanReadableCopyright)
