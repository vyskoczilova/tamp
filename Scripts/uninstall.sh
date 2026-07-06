#!/usr/bin/env bash
# Cleanly remove Tamp from this Mac. macOS does not do this for you: deleting
# the .app leaves the login-item registration and the "Allow in the Menu Bar"
# entry behind, and a running keep-awake session would outlive the app. This
# script tears all of that down (including leftovers from the pre-rename
# "Coffee" install).
#
# Usage:
#   Scripts/uninstall.sh          # prompt before removing
#   Scripts/uninstall.sh --yes    # no prompt
set -euo pipefail

APP="/Applications/Tamp.app"
BUNDLE_ID="cz.kybernaut.tamp"
STATE_DIR="$HOME/Library/Application Support/Tamp"
STATE_FILE="$STATE_DIR/state.json"

# Pre-rename install (product was called "Coffee" before v1.0.0).
LEGACY_APP="/Applications/Coffee.app"
LEGACY_BUNDLE_ID="cz.kybernaut.coffee"
LEGACY_STATE_DIR="$HOME/Library/Application Support/Coffee"

ASSUME_YES=false
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=true

echo "This will remove Tamp:"
echo "  • stop any active keep-awake session"
echo "  • unregister the launch-at-login item"
echo "  • delete $APP"
echo "  • delete $STATE_DIR"
echo "  • clear the $BUNDLE_ID preferences"
echo "  • remove any pre-rename Coffee install ($LEGACY_APP, state, prefs)"
echo
if ! $ASSUME_YES; then
    read -r -p "Proceed? [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "Aborted."; exit 0; }
fi

# 1. Stop our tracked caffeinate so we don't orphan a keep-awake process. We only
#    ever kill the PID Tamp recorded — never every caffeinate on the system —
#    and only if that PID still names a caffeinate (PIDs get recycled).
for state in "$STATE_FILE" "$LEGACY_STATE_DIR/state.json"; do
    if [[ -f "$state" ]]; then
        PID="$(plutil -extract pid raw -o - "$state" 2>/dev/null || true)"
        if [[ -n "${PID:-}" && "$PID" =~ ^[0-9]+$ ]] \
            && [[ "$(ps -p "$PID" -o comm= 2>/dev/null)" == *caffeinate ]]; then
            echo "==> Stopping tracked caffeinate (pid $PID)…"
            kill "$PID" 2>/dev/null || true
        fi
    fi
done

# 2. Unregister the login item. SMAppService.mainApp is bundle-scoped, so this
#    must run from the installed bundle's own binary (see main.swift). Resolve
#    the executable from the bundle rather than assuming its name.
for app in "$APP" "$LEGACY_APP"; do
    if [[ -d "$app" ]]; then
        EXE="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$app/Contents/Info.plist" 2>/dev/null || true)"
        EXE_PATH="$app/Contents/MacOS/$EXE"
        if [[ -n "$EXE" && -x "$EXE_PATH" ]]; then
            echo "==> Unregistering login item ($app)…"
            "$EXE_PATH" --unregister-login || true
        fi
    fi
done

# 3. Quit the menu bar app (new bundles run as "Tamp"; bare dev runs as
#    "TampBar"; pre-rename installs as "Coffee"/"CoffeeBar").
echo "==> Quitting Tamp…"
pkill -x Tamp 2>/dev/null || true
pkill -x TampBar 2>/dev/null || true
pkill -x Coffee 2>/dev/null || true
pkill -x CoffeeBar 2>/dev/null || true
sleep 1

# 4. Remove the app bundles.
echo "==> Removing ${APP}…"
rm -rf "$APP" "$LEGACY_APP"

# 5. Remove shared state and preferences (current and pre-rename).
echo "==> Removing state and preferences…"
rm -rf "$STATE_DIR" "$LEGACY_STATE_DIR"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
defaults delete "$LEGACY_BUNDLE_ID" 2>/dev/null || true

echo
echo "==> Done. Tamp has been removed."
echo "Note: the stale 'Tamp' entry under System Settings ▸ Control Center ▸"
echo "\"Allow in the Menu Bar\" is cleared by macOS on next login (or toggle it off)."
