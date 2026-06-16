## UX / menu

## Features

[ ] "While app runs" — coffee while Xcode — keeps Mac awake as long as a named
    app is open (uses caffeinate -w <pid>). Useful for builds, video calls, etc.

[ ] Recurring schedules — "keep awake weekdays 9–17" — needs a scheduler layer.

## Distribution

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
[x] Custom brewing-concept icons (Pour-Over, French Press, Tamper, Chemex) from
    bundled SVG template artwork via IconRenderer + Bundle.module
