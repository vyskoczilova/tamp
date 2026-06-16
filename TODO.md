## UX / menu

[ ] brewing-concept icon styles (pourOver, espresso, frenchPress, kettle) all
    fall back to cup.and.saucer SF Symbol — visually identical to "Cup".
    Fix: find distinct SF Symbols per style, or add custom template image assets.

[ ] "Prevent Sleep Of" submenu — defaults are Display ✓, System ✓, Disk ✗
    (maps to caffeinate -d -i; -m is disk). Most users don't need to change this.
    Move it out of the main menu into a Settings panel or a secondary "…" item.

[ ] Settings panel — preferences (sleep flags, icon style) currently live inside
    the menu itself and feel buried. Consider a small NSPanel or popover so the
    menu only shows actions (Toggle, Keep Awake For, Custom…, Quit).

## Features

[ ] "While app runs" — coffee while Xcode — keeps Mac awake as long as a named
    app is open (uses caffeinate -w <pid>). Useful for builds, video calls, etc.

[ ] Recurring schedules — "keep awake weekdays 9–17" — needs a scheduler layer.

## Preferences & Credits

[ ] Preferences panel — expose icon style picker, sleep flags, and launch-at-login
    in a dedicated Settings window (NSPanel or SwiftUI Settings scene) rather than
    burying them in the menu.

[ ] Credits / About panel — show app name, version, author name, and a link to the
    repo or personal site. Could be a simple NSAlert or a small About window.

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
