#!/bin/bash
# The 7thDroid AppImage's entry point: the installer the first time, then a menu to launch 7th Heaven,
# update or repair it, redo its shortcuts, read the log or uninstall it.

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR=$ROOT_DIR/lib
ASSETS_DIR=$ROOT_DIR/assets

# shellcheck source=lib/common.sh
. "$LIB_DIR/common.sh"
# shellcheck source=lib/droiddeck.sh
. "$LIB_DIR/droiddeck.sh"
# shellcheck source=lib/shortcuts.sh
. "$LIB_DIR/shortcuts.sh"

ui_init
[ "$UI_MODE" = none ] && die "7thDroid needs a terminal or its bundled zenity to ask questions."

COMPATDATA='' action=''

installed() {
  load_state 2>/dev/null && [ -f "$LAUNCHER" ] && [ -f "$COMPATDATA/pfx/drive_c/7th Heaven/7th Heaven.exe" ]
}

installer() {
  bash "$ROOT_DIR/install.sh" "$@"
}

installed || exec bash "$ROOT_DIR/install.sh" "$@"

while true; do
  choose action "7th Heaven ${SEVENTH_TAG:+$SEVENTH_TAG }is installed for ${FF7_VERSION:-FINAL FANTASY VII}." \
    "Launch 7th Heaven" \
    "Update or repair 7th Heaven" \
    "Add or redo shortcuts" \
    "Show the last log" \
    "Uninstall 7th Heaven" \
    "Quit"
  case $action in
    0) exec bash "$LAUNCHER" ;;
    1) installer ;;
    2) installer --shortcuts-only ;;
    3)
      if [ "$UI_MODE" = zenity ]; then
        zen --text-info --width=1000 --height=700 --filename="$LOG_FILE" || true
      else
        less "$LOG_FILE" 2>/dev/null || cat "$LOG_FILE"
      fi ;;
    4) installer --uninstall; installed || exit 0 ;;
    *) exit 0 ;;
  esac
  installed || exit 0
  load_state
done
