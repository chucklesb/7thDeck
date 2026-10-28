# shellcheck shell=bash
# Everything that talks to DroidDeck's own helpers. Each path can be overridden from the environment,
# so a renamed or moved helper in a future DroidDeck build is a one-variable fix.

STEAM_ROOT=${STEAM_ROOT:-$HOME/.local/share/Steam}
PROTON_RUN=${DROIDDECK_PROTON_RUN:-$(command -v droiddeck-proton-run 2>/dev/null || echo /usr/local/bin/droiddeck-proton-run)}
INNOEXTRACT=${DROIDDECK_INNOEXTRACT:-$(command -v droiddeck-innoextract 2>/dev/null || command -v innoextract 2>/dev/null || echo /usr/local/bin/droiddeck-innoextract)}
MSITOOLS_DIR=${DROIDDECK_MSITOOLS:-/usr/local/lib/droiddeck-msitools}
SHORTCUTS_TOOL=${DROIDDECK_STEAM_SHORTCUTS:-$(command -v droiddeck-steam-shortcuts 2>/dev/null || echo /usr/local/bin/droiddeck-steam-shortcuts)}
APPS_DIR=${DROIDDECK_APPS_DIR:-/opt/droiddeck-apps}
EXTRA_LIBRARIES=(/mnt/droiddeck-sd /mnt/droiddeck)
PROTON_DEPOTS=("Proton Experimental (ARM64)" "Proton 11.0 (ARM64)")

# The FEX settings DroidDeck's droiddeck-game-env gives .NET programs (DOTNET_FEX). x87 full precision
# is also what keeps InnoSetup installers from aborting with "File not fpund".
DOTNET_FEX=(
  FEX_TSOENABLED=1
  FEX_VECTORTSOENABLED=1
  FEX_MEMCPYSETTSOENABLED=1
  FEX_HALFBARRIERTSOENABLED=1
  FEX_X87REDUCEDPRECISION=0
  FEX_MULTIBLOCK=0
)

HAVE_INNOEXTRACT=0
HAVE_7Z=0
HAVE_SHORTCUTS_TOOL=0
HAVE_APPS_DIR=0

preflight() {
  local missing=()
  [ -x "$PROTON_RUN" ] || missing+=("droiddeck-proton-run (looked for $PROTON_RUN; set DROIDDECK_PROTON_RUN to override)")
  [ -d "$STEAM_ROOT" ] || missing+=("a Steam installation at $STEAM_ROOT (set STEAM_ROOT to override, or open Steam in DroidDeck once)")
  have curl || missing+=("curl")
  have python3 || missing+=("python3")
  if [ ${#missing[@]} -gt 0 ]; then
    printf '    Missing: %s\n' "${missing[@]}" >&2
    die "$APP_NAME needs the pieces above. It is meant to run inside DroidDeck's Linux environment."
  fi
  debug "droiddeck-proton-run: $PROTON_RUN"
  debug "Steam root: $STEAM_ROOT"

  [ -x "$INNOEXTRACT" ] && HAVE_INNOEXTRACT=1
  [ -x "$MSITOOLS_DIR/7z" ] && HAVE_7Z=1
  [ -f "$SHORTCUTS_TOOL" ] && HAVE_SHORTCUTS_TOOL=1
  [ -d "$APPS_DIR" ] && [ -w "$APPS_DIR" ] && HAVE_APPS_DIR=1
  if [ "$HAVE_INNOEXTRACT" = 1 ]; then debug "innoextract: $INNOEXTRACT"; else info "innoextract not found: installers will be run instead of unpacked."; fi
  if [ "$HAVE_7Z" = 1 ]; then debug "7z: $MSITOOLS_DIR/7z"; else info "7z not found: CD images (.iso) cannot be unpacked; extracted disc folders still work."; fi
  if [ "$HAVE_SHORTCUTS_TOOL" = 1 ]; then debug "steam shortcuts tool: $SHORTCUTS_TOOL"; else info "droiddeck-steam-shortcuts not found: adding to Steam is unavailable."; fi
  if [ "$HAVE_APPS_DIR" = 1 ]; then debug "app entries: $APPS_DIR"; else info "$APPS_DIR not found: adding to the DroidDeck app is unavailable."; fi
  ok "DroidDeck helpers found."
}

sevenzip() {
  LD_LIBRARY_PATH=$MSITOOLS_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} "$MSITOOLS_DIR/7z" "$@"
}

# Steam library roots (folders that hold steamapps/), each once.
steam_libraries() {
  python - "$STEAM_ROOT" "${EXTRA_LIBRARIES[@]}" <<'EOF'
import os, re, sys
root, extra = sys.argv[1], sys.argv[2:]
candidates = [root]
for vdf in ("steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"):
    try:
        with open(os.path.join(root, vdf), encoding="utf-8", errors="replace") as f:
            candidates += [m.replace("\\\\", "\\") for m in re.findall(r'"path"\s+"([^"]+)"', f.read())]
    except OSError:
        pass
seen = set()
for lib in candidates + extra:
    try:
        st = os.stat(os.path.join(lib, "steamapps"))
    except OSError:
        continue
    if (st.st_dev, st.st_ino) not in seen:
        seen.add((st.st_dev, st.st_ino))
        print(lib)
EOF
}

# acf_value FILE KEY
acf_value() {
  sed -n 's/^[[:space:]]*"'"$2"'"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/Ip' "$1" 2>/dev/null | head -n1
}

# steam_app_installed APPID -> prints "library<TAB>install dir" when fully installed
steam_app_installed() {
  local appid=$1 lib manifest dir flags
  while IFS= read -r lib; do
    manifest=$lib/steamapps/appmanifest_$appid.acf
    [ -f "$manifest" ] || continue
    flags=$(acf_value "$manifest" StateFlags)
    dir=$(acf_value "$manifest" installdir)
    [[ $flags =~ ^[0-9]+$ ]] && [ $((flags & 4)) -ne 0 ] || continue
    [ -n "$dir" ] && [ -d "$lib/steamapps/common/$dir" ] || continue
    printf '%s\t%s\n' "$lib" "$lib/steamapps/common/$dir"
    return 0
  done < <(steam_libraries)
  return 1
}

# The ARM64 Proton depot droiddeck-proton starts, or a third-party Windows tool in compatibilitytools.d.
proton_available() {
  local lib name tool
  while IFS= read -r lib; do
    for name in "${PROTON_DEPOTS[@]}"; do
      if [ -d "$lib/steamapps/common/$name/files/bin-arm64" ] && [ -x "$lib/steamapps/common/$name/proton" ]; then
        printf '%s\n' "$lib/steamapps/common/$name"
        return 0
      fi
    done
  done < <(steam_libraries)
  for tool in "$STEAM_ROOT"/compatibilitytools.d/*/; do
    [ -f "$tool/compatibilitytool.vdf" ] && [ -f "$tool/proton" ] || continue
    grep -qi '"from_oslist"[[:space:]]*"[^"]*windows' "$tool/compatibilitytool.vdf" || continue
    printf '%s\n' "${tool%/}"
    return 0
  done
  return 1
}

ensure_proton() {
  step "Checking for Proton"
  local found
  while ! found=$(proton_available); do
    [ "$DRY_RUN" = 1 ] && { warn "No ARM64 Proton found (continuing because of --dry-run)."; return; }
    warn "No ARM64 Proton is installed yet."
    info "Open Steam in DroidDeck and let it finish downloading Proton, FEX and the Steam Linux Runtime."
    info "This sometimes takes more than one start of Steam."
    [ "$ASSUME_YES" = 1 ] && die "Proton is missing."
    pause "When Steam has finished downloading,"
  done
  ok "Found $found"
}

# Is a wineserver running for this compatdata's prefix?
prefix_busy() {
  local pfx=${1%/}/pfx p comm
  for p in /proc/[0-9]*; do
    comm=$(cat "$p/comm" 2>/dev/null) || continue
    [[ $comm == wineserver* ]] || continue
    tr '\0' '\n' < "$p/environ" 2>/dev/null | grep -Fxq -e "WINEPREFIX=$pfx" -e "WINEPREFIX=$pfx/" && return 0
  done
  return 1
}

# wait_prefix_idle COMPATDATA [timeout seconds]
wait_prefix_idle() {
  local compatdata=$1 limit=${2:-3600} waited=0
  [ "$DRY_RUN" = 1 ] && return 0
  sleep 2
  while prefix_busy "$compatdata"; do
    if [ $waited -eq 0 ]; then info "Waiting for Windows programs in the prefix to finish..."; fi
    sleep 3
    waited=$((waited + 3))
    [ $waited -ge "$limit" ] && { warn "Still busy after ${limit}s; continuing."; return 1; }
  done
  return 0
}

# The arguments that make droiddeck-proton-run use COMPATDATA for PROGRAM. A program inside the prefix's
# drive_c is matched to it by droiddeck-proton-run itself; --prefix ID only reaches the client's own
# steamapps/compatdata, so a program outside a prefix in another library is copied into drive_c first.
prefix_target() {
  local compatdata=${1%/} program=$2 id staged
  id=${compatdata##*/}
  case $program in
    "$compatdata"/pfx/*) printf '%s\n' "$program"; return ;;
  esac
  if [ "$compatdata" = "$STEAM_ROOT/steamapps/compatdata/$id" ]; then
    printf '%s\n%s\n%s\n' --prefix "$id" "$program"
    return
  fi
  staged=$compatdata/pfx/drive_c/$APP_ID-setup/${program##*/}
  if [ "$DRY_RUN" != 1 ]; then
    { mkdir -p "${staged%/*}" && cp -f "$program" "$staged"; } || die "Could not copy ${program##*/} into the prefix."
  fi
  printf '%s\n' "$staged"
}

# proton_run COMPATDATA PROGRAM [ARGS...] - a normal launch: the user's game environment applies.
proton_run() {
  local compatdata=$1 program=$2 target=()
  shift 2
  check_compatdata "$compatdata"
  mapfile -t target < <(prefix_target "$compatdata" "$program")
  run "$PROTON_RUN" "${target[@]}" "$@"
}

# fex_run COMPATDATA PROGRAM [ARGS...] - for installers. The run verb keeps droiddeck-game-env from
# applying the user's FEX preset, so the DOTNET_FEX values set here are the ones FEX sees.
fex_run() {
  local compatdata=$1 program=$2 target=() rc
  shift 2
  check_compatdata "$compatdata"
  mapfile -t target < <(prefix_target "$compatdata" "$program")
  run env "${DOTNET_FEX[@]}" "$PROTON_RUN" --verb run "${target[@]}" "$@"
  rc=$?
  wait_prefix_idle "$compatdata"
  return $rc
}

# droiddeck-proton-run --prefix ID always uses the client's own steamapps/compatdata/ID.
compatdata_for() {
  [[ $1 =~ ^[1-9][0-9]*$ ]] || die "Not a prefix id: '$1'"
  printf '%s\n' "$STEAM_ROOT/steamapps/compatdata/$1"
}

# Every prefix path ends in steamapps/compatdata/<number>; anything else is a bug, and must never
# turn into paths like /pfx.
check_compatdata() {
  [[ $1 =~ /steamapps/compatdata/-?[0-9]+$ ]] || die "Internal error: bad prefix path '$1'"
}

steam_running() {
  local p comm
  for p in /proc/[0-9]*; do
    comm=$(cat "$p/comm" 2>/dev/null) || continue
    case $comm in steam|steamwebhelper) return 0 ;; esac
  done
  return 1
}
