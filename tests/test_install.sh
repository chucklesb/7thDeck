#!/bin/bash
# End-to-end runs of install.sh against fixture trees, with tests/stubs/droiddeck-proton-run standing in
# for DroidDeck. DROIDDECK_SRC (a DroidDeck checkout) enables the Steam shortcut checks.
set -u
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DROIDDECK_SRC=${DROIDDECK_SRC:-}
DD_BIN=${DROIDDECK_SRC:+$DROIDDECK_SRC/tools/linuxfs/overlay/usr/local/bin}
FAILED=0 PASSED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }
check() { local name=$1; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# Removes the current fixture home, which is always a mktemp directory. KEEP=1 leaves it for debugging.
cleanup() {
  [ -n "${KEEP:-}" ] && { echo "  kept $T"; return; }
  case ${T:-} in
    "${TMPDIR:-/tmp}"/tmp.?*) rm -rf -- "$T" ;;
  esac
}

# fixture NAME -> sets T (a fresh fake home) and the environment install.sh reads
fixture() {
  T=$(mktemp -d)
  export HOME=$T XDG_CONFIG_HOME=$T/.config XDG_DATA_HOME=$T/.local/share XDG_CACHE_HOME=$T/.cache XDG_STATE_HOME=$T/.local/state
  export STEAM_ROOT=$T/.local/share/Steam STUB_LOG=$T/stub.log
  export DROIDDECK_PROTON_RUN=$REPO/tests/stubs/droiddeck-proton-run
  export DROIDDECK_INNOEXTRACT=$T/none DROIDDECK_MSITOOLS=$T/none
  export DROIDDECK_APPS_DIR=$T/opt/droiddeck-apps
  export DROIDDECK_STEAM_SHORTCUTS=${DD_BIN:+$DD_BIN/droiddeck-steam-shortcuts}
  [ -n "$DROIDDECK_STEAM_SHORTCUTS" ] || DROIDDECK_STEAM_SHORTCUTS=$T/none
  mkdir -p "$STEAM_ROOT/steamapps/common/Proton Experimental (ARM64)/files/bin-arm64" "$DROIDDECK_APPS_DIR" \
    "$STEAM_ROOT/config" "$STEAM_ROOT/userdata/12345/config"
  touch "$STEAM_ROOT/steamapps/common/Proton Experimental (ARM64)/proton"
  chmod +x "$STEAM_ROOT/steamapps/common/Proton Experimental (ARM64)/proton"
  printf '"users"\n{\n\t"76561197960278073"\n\t{\n\t\t"MostRecent"\t"1"\n\t}\n}\n' > "$STEAM_ROOT/config/loginusers.vdf"
  # cached downloads, so no test touches the network
  mkdir -p "$XDG_CACHE_HOME/7thdroid"
  for f in 7thHeaven-v4.5.2.0_Release.exe windowsdesktop-runtime-10.0.14-win-x64.exe windowsdesktop-runtime-10.0.14-win-x86.exe; do
    echo stub > "$XDG_CACHE_HOME/7thdroid/$f"
  done
  : > "$STUB_LOG"
}

steam_game() { # LIBRARY APPID INSTALLDIR EXE
  mkdir -p "$1/steamapps/common/$3" "$1/steamapps/compatdata/$2/pfx/drive_c/users/steamuser/Documents"
  touch "$1/steamapps/common/$3/$4"
  printf 'WINE REGISTRY Version 2\n' > "$1/steamapps/compatdata/$2/pfx/system.reg"
  printf 'WINE REGISTRY Version 2\n\n#arch=win64\n' > "$1/steamapps/compatdata/$2/pfx/user.reg"
  printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"%s"\n}\n' "$2" "$3" > "$1/steamapps/appmanifest_$2.acf"
}

installer() { bash "$REPO/install.sh" --yes --version pinned "$@" > "$T/out.log" 2>&1; }
settings() { cat "$1/pfx/drive_c/7th Heaven/7thWorkshop/settings.xml"; }

echo "Steam 2026 release in a second library"
fixture
mkdir -p "$T/sd"
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$STEAM_ROOT" "$T/sd" > "$STEAM_ROOT/steamapps/libraryfolders.vdf"
steam_game "$T/sd" 3837340 "FINAL FANTASY VII" FFVII.exe
CD=$T/sd/steamapps/compatdata/3837340
check "installer succeeds" installer --no-steam
check "installers ran in FF7's prefix" grep -q $'run\t3837340\t7thHeaven-v4.5.2.0_Release.exe\t0' "$STUB_LOG"
check "installers ran with full x87 precision" bash -c "! cut -f4 '$STUB_LOG' | grep -vqx 0"
check "installers were staged into drive_c" test -f "$CD/pfx/drive_c/7thdroid-setup/7thHeaven-v4.5.2.0_Release.exe"
check ".NET x64 and x86" test -d "$CD/pfx/drive_c/Program Files (x86)/dotnet/shared/Microsoft.WindowsDesktop.App/10.0.14"
check "Avalon.Graphics in user.reg" grep -q '"DisableHWAcceleration"=dword:00000001' "$CD/pfx/user.reg"
check "dinput override in user.reg" grep -q '"dinput"="native,builtin"' "$CD/pfx/user.reg"
check "FF7Exe is the game's FFVII.exe" grep -qF "<FF7Exe>Z:${T//\//\\}\\sd\\steamapps\\common\\FINAL FANTASY VII\\FFVII.exe</FF7Exe>" <(settings "$CD")
check "version SteamReRelease" grep -q '<FF7InstalledVersion>SteamReRelease</FF7InstalledVersion>' <(settings "$CD")
check "timeout.exe" test -f "$CD/pfx/drive_c/windows/system32/timeout.exe"
check "launcher runs the prefix's 7th Heaven" grep -qF "$CD/pfx/drive_c/7th\\ Heaven/7th\\ Heaven.exe" "$T/.local/share/7thdroid/7th Heaven.sh"
check "app entry" test "$(cat "$T/opt/droiddeck-apps/7thheaven/entry")" = "7th Heaven.sh"
check "KDE entry" test -f "$T/.local/share/applications/7th-heaven.desktop"
check "second run skips finished steps" bash -c "cp '$STUB_LOG' '$T/first.log'; bash '$REPO/install.sh' --yes --version pinned --no-steam >/dev/null 2>&1 && cmp -s '$STUB_LOG' '$T/first.log'"
cleanup

echo "Steam 2013 release, launch entries declined"
fixture
steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
CD=$STEAM_ROOT/steamapps/compatdata/39140
check "installer succeeds" installer --no-app-entry --no-steam --no-desktop
check "version Steam" grep -q '<FF7InstalledVersion>Steam</FF7InstalledVersion>' <(settings "$CD")
check "user slot" test -d "$CD/pfx/drive_c/users/steamuser/Documents/Square Enix/FINAL FANTASY VII Steam/user_12345678"
check "no app entry" test ! -e "$T/opt/droiddeck-apps/7thheaven"
check "no KDE entry" test ! -e "$T/.local/share/applications/7th-heaven.desktop"
cleanup

echo "GOG through Heroic (Flatpak)"
fixture
mkdir -p "$T/Games/Heroic/FINAL FANTASY VII" "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store"
touch "$T/Games/Heroic/FINAL FANTASY VII/FFVII.exe"
printf '{"installed":[{"appName":"1698970154","install_path":"%s","platform":"windows"}]}' "$T/Games/Heroic/FINAL FANTASY VII" \
  > "$T/.var/app/com.heroicgameslauncher.hgl/config/heroic/gog_store/installed.json"
check "installer succeeds" installer --no-steam
check "detected as Heroic Flatpak" grep -q "GOG via Heroic (Flatpak)" "$T/out.log"
ID=$(python3 "$REPO/lib/steam_shortcut.py" appid "$T/.local/share/7thdroid/7th Heaven.sh" "7th Heaven")
check "dedicated prefix named after the shortcut id" test -f "$STEAM_ROOT/steamapps/compatdata/$ID/pfx/drive_c/7th Heaven/7th Heaven.exe"
check "first run used --prefix" grep -q $'run\t'"$ID"$'\twindowsdesktop-runtime-10.0.14-win-x64.exe' "$STUB_LOG"
check "version GOG" grep -q '<FF7InstalledVersion>GOG</FF7InstalledVersion>' <(settings "$STEAM_ROOT/steamapps/compatdata/$ID")
check "drive label" test "$(cat "$STEAM_ROOT/steamapps/compatdata/$ID/pfx/drive_c/.windows-label")" = FF7DISC1
cleanup

echo "GOG through Lutris and through the DroidDeck app"
fixture
mkdir -p "$T/Games/final-fantasy-vii/drive_c/GOG Games/FF7" "$T/.local/share/lutris" "$T/Games/Stores/GOG/FINAL FANTASY VII"
touch "$T/Games/final-fantasy-vii/drive_c/GOG Games/FF7/FFVII.exe" "$T/Games/Stores/GOG/FINAL FANTASY VII/FFVII.exe"
python3 -c "
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('CREATE TABLE games (id INTEGER, slug TEXT, directory TEXT, installed INTEGER, service TEXT, service_id TEXT)')
con.execute('INSERT INTO games VALUES (1, ?, ?, 1, ?, ?)', ('final-fantasy-vii', sys.argv[2], 'gog', '1698970154'))
con.commit()" "$T/.local/share/lutris/pga.db" "$T/Games/final-fantasy-vii"
printf '{"version":1,"store":"gog","id":"1698970154","title":"FINAL FANTASY VII","exe":"FFVII.exe"}' > "$T/Games/Stores/GOG/FINAL FANTASY VII/.droiddeck-store.json"
check "installer succeeds" installer --no-steam
check "DroidDeck store found" grep -q "GOG via the DroidDeck app" "$T/out.log"
check "Lutris found, game folder inside its prefix" grep -qF "GOG via Lutris (native/AppImage) - $T/Games/final-fantasy-vii/drive_c/GOG Games/FF7" "$T/out.log"
cleanup

echo "GOG installer, run because innoextract is missing"
fixture
mkdir -p "$T/Download"
echo stub > "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe"
check "installer succeeds" installer --no-steam --source "$T/Download/setup_final_fantasy_vii_2.0_(gog).exe" --game-dir "$T/Games/FF7"
check "GOG installer ran with full x87 precision" grep -q $'\tsetup_final_fantasy_vii_2.0_(gog).exe\t0\t' "$STUB_LOG"
check "game installed where asked" test -f "$T/Games/FF7/FFVII.exe"
cleanup

echo "1998 CD-ROM from disc folders"
fixture
mkdir -p "$T/cd1/FF7" "$T/cd2/FF7"
echo stub > "$T/cd1/SETUP.EXE"
check "installer succeeds" installer --no-steam --source "$T/cd1" --source "$T/cd2"
ID=$(python3 "$REPO/lib/steam_shortcut.py" appid "$T/.local/share/7thdroid/7th Heaven.sh" "7th Heaven")
PFX=$STEAM_ROOT/steamapps/compatdata/$ID/pfx
check "discs mapped to d: and e:" test "$(readlink "$PFX/dosdevices/e:")" = "$T/cd2"
check "disc labels" test "$(cat "$T/cd2/.windows-label")" = FF7DISC2
check "CD drive type" grep -q '"e:"="cdrom"' "$PFX/system.reg"
check "version Original98" grep -q '<FF7InstalledVersion>Original98</FF7InstalledVersion>' <(settings "${PFX%/pfx}")
cleanup

if [ -n "$DD_BIN" ]; then
  echo "Steam shortcut (DroidDeck's shortcuts.vdf code)"
  fixture
  steam_game "$STEAM_ROOT" 39140 "FINAL FANTASY VII" ff7_en.exe
  check "installer succeeds" installer --steam
  check "shortcut readable by DroidDeck and untagged" python3 - "$DD_BIN/droiddeck-steam-shortcuts" "$STEAM_ROOT/userdata/12345/config/shortcuts.vdf" "$T/.local/share/7thdroid/7th Heaven.sh" <<'EOF'
import runpy, sys
tool = runpy.run_path(sys.argv[1])
items = list(tool["parse"](open(sys.argv[2], "rb").read())["shortcuts"].values())
assert len(items) == 1 and items[0]["Exe"] == '"%s"' % sys.argv[3] and items[0]["tags"] == {}, items
EOF
  check "re-adding replaces it" bash -c "bash '$REPO/install.sh' --yes --shortcuts-only --steam --no-app-entry --no-desktop >/dev/null 2>&1 && python3 - <<'EOF'
import runpy
tool = runpy.run_path('$DD_BIN/droiddeck-steam-shortcuts')
assert len(tool['parse'](open('$STEAM_ROOT/userdata/12345/config/shortcuts.vdf', 'rb').read())['shortcuts']) == 1
EOF"
  cleanup
fi

echo "Missing DroidDeck"
fixture
export DROIDDECK_PROTON_RUN=$T/none
check "names what is missing" bash -c "! bash '$REPO/install.sh' --yes >'$T/out.log' 2>&1 && grep -q 'droiddeck-proton-run' '$T/out.log'"
cleanup

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
