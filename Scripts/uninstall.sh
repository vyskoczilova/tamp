#!/usr/bin/env bash
# Cleanly remove Coffee from this Mac. macOS does not do this for you: deleting
# the .app leaves the login-item registration and the "Allow in the Menu Bar"
# entry behind, and a running keep-awake session would outlive the app. This
# script tears all of that down.
#
# Usage:
#   Scripts/uninstall.sh          # prompt before removing
#   Scripts/uninstall.sh --yes    # no prompt
set -euo pipefail

APP="/Applications/Coffee.app"
BUNDLE_ID="cz.kybernaut.coffee"
STATE_DIR="$HOME/Library/Application Support/Coffee"
STATE_FILE="$STATE_DIR/state.json"

ASSUME_YES=false
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=true

echo "This will remove Coffee:"
echo "  • stop any active keep-awake session"
echo "  • unregister the launch-at-login item"
echo "  • delete $APP"
echo "  • delete $STATE_DIR"
echo "  • clear the $BUNDLE_ID preferences"
echo
if ! $ASSUME_YES; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 0; }
fi

# 1. Stop our tracked caffeinate so we don't orphan a keep-awake process. We only
#    ever kill the PID Coffee recorded — never every caffeinate on the system —
#    and only if that PID still names a caffeinate (PIDs get recycled).
if [[ -f "$STATE_FILE" ]]; then
    PID="$(plutil -extract pid raw -o - "$STATE_FILE" 2>/dev/null || true)"
    if [[ -n "${PID:-}" && "$PID" =~ ^[0-9]+$ ]] \
        && [[ "$(ps -p "$PID" -o comm= 2>/dev/null)" == *caffeinate ]]; then
        echo "==> Stopping tracked caffeinate (pid $PID)…"
        kill "$PID" 2>/dev/null || true
    fi
fi

# 2. Unregister the login item. SMAppService.mainApp is bundle-scoped, so this
#    must run from the installed bundle's own binary (see main.swift). Resolve
#    the executable from the bundle rather than assuming its name — older
#    installs shipped it as "CoffeeBar", newer ones as "Coffee".
if [[ -d "$APP" ]]; then
    EXE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP/Contents/Info.plist" 2>/dev/null || true)"
    EXE_PATH="$APP/Contents/MacOS/$EXE"
    if [[ -n "$EXE" && -x "$EXE_PATH" ]]; then
        echo "==> Unregistering login item…"
        "$EXE_PATH" --unregister-login || true
    fi
fi

# 3. Quit the menu bar app (new bundles run as "Coffee"; older ones "CoffeeBar").
echo "==> Quitting Coffee…"
pkill -x Coffee 2>/dev/null || true
pkill -x CoffeeBar 2>/dev/null || true
sleep 1

# 4. Remove the app bundle.
echo "==> Removing ${APP}…"
rm -rf "$APP"

# 5. Remove shared state and preferences.
echo "==> Removing state and preferences…"
rm -rf "$STATE_DIR"
defaults delete "$BUNDLE_ID" 2>/dev/null || true

echo
echo "==> Done. Coffee has been removed."
echo "Note: the stale 'Coffee' entry under System Settings ▸ Control Center ▸"
echo "\"Allow in the Menu Bar\" is cleared by macOS on next login (or toggle it off)."
