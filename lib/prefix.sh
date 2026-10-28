# shellcheck shell=bash
# Preparing the Proton prefix: .NET Desktop runtimes, registry fixes and the small files FF7 expects.

DOTNET_FALLBACK=10.0.14
DOTNET_BUILDS=https://builds.dotnet.microsoft.com/dotnet
LIB_DIR=${LIB_DIR:-$(dirname "${BASH_SOURCE[0]}")}

# dotnet_installed COMPATDATA x64|x86 MAJOR.MINOR
dotnet_installed() {
  local drive=$1/pfx/drive_c folder
  [ "$2" = x64 ] && folder="Program Files" || folder="Program Files (x86)"
  compgen -G "$drive/$folder/dotnet/shared/Microsoft.WindowsDesktop.App/$3.*" >/dev/null
}

# The newest Windows Desktop runtime of a MAJOR.MINOR channel, from Microsoft's release metadata.
dotnet_latest_patch() {
  curl -fsSL --retry 3 "$DOTNET_BUILDS/release-metadata/$1/releases.json" 2>/dev/null | python -c '
import json, sys
data = json.load(sys.stdin)
for release in data.get("releases", []):
    desktop = release.get("windowsdesktop") or {}
    if desktop.get("version") and "-" not in desktop["version"]:
        print(desktop["version"])
        break
'
}

install_dotnet() {
  local compatdata=$1 version=$2 channel arch file
  channel=${version%.*}
  for arch in x64 x86; do
    if dotnet_installed "$compatdata" "$arch" "$channel" && [ "$REINSTALL" != 1 ]; then
      ok ".NET Desktop Runtime $channel ($arch) is already installed."
      continue
    fi
    file=$(download "$DOTNET_BUILDS/WindowsDesktop/$version/windowsdesktop-runtime-$version-win-$arch.exe")
    info "Installing .NET Desktop Runtime $version ($arch)"
    fex_run "$compatdata" "$file" /install /quiet /norestart || warn "The .NET $arch installer reported an error."
    if [ "$DRY_RUN" != 1 ] && ! dotnet_installed "$compatdata" "$arch" "$channel"; then
      die ".NET Desktop Runtime $version ($arch) did not install. See $LOG_FILE."
    fi
  done
}

# apply_registry COMPATDATA - with the prefix idle, edit user.reg and system.reg directly.
apply_registry() {
  local compatdata=$1 pfx=$1/pfx user_ops system_ops drive
  user_ops=(
    'Software\Microsoft\Avalon.Graphics' DisableHWAcceleration dword:1
    'Software\Wine\DllOverrides' dinput 'str:native,builtin'
  )
  system_ops=()
  for drive in "${CD_DRIVES[@]}"; do
    system_ops+=('Software\Wine\Drives' "$drive" str:cdrom)
  done
  info "Registry: WinForms/WPF hardware acceleration off, dinput native first${CD_DRIVES:+, CD drives ${CD_DRIVES[*]}}"
  [ "$DRY_RUN" = 1 ] && return 0
  wait_prefix_idle "$compatdata" 120 || die "The prefix is still in use. Close any game or program running in it and try again."
  if [ -f "$pfx/user.reg" ] && python "$LIB_DIR/regedit.py" "$pfx/user.reg" "${user_ops[@]}" \
     && { [ ${#system_ops[@]} -eq 0 ] || python "$LIB_DIR/regedit.py" "$pfx/system.reg" "${system_ops[@]}"; }; then
    return 0
  fi
  warn "Editing the registry files failed; using reg.exe instead."
  registry_with_reg_exe "$compatdata"
}

registry_with_reg_exe() {
  local compatdata=$1 regfile drive
  regfile=$compatdata/pfx/drive_c/$APP_ID-setup/fixes.reg
  mkdir -p "${regfile%/*}"
  {
    printf 'Windows Registry Editor Version 5.00\r\n\r\n'
    printf '[HKEY_CURRENT_USER\\Software\\Microsoft\\Avalon.Graphics]\r\n"DisableHWAcceleration"=dword:00000001\r\n\r\n'
    printf '[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\r\n"dinput"="native,builtin"\r\n\r\n'
    if [ ${#CD_DRIVES[@]} -gt 0 ]; then
      printf '[HKEY_LOCAL_MACHINE\\Software\\Wine\\Drives]\r\n'
      for drive in "${CD_DRIVES[@]}"; do printf '"%s"="cdrom"\r\n' "$drive"; done
    fi
  } > "$regfile"
  fex_run "$compatdata" "$compatdata/pfx/drive_c/windows/system32/reg.exe" import "C:\\$APP_ID-setup\\fixes.reg" \
    || die "reg.exe could not import the registry fixes."
}

# The optional winetricks dinput verb, from a Proton build that ships protonfixes (e.g. DroidDeck-Proton).
winetricks_dinput() {
  local compatdata=$1 tool winetricks
  for winetricks in "$STEAM_ROOT"/compatibilitytools.d/*/protonfixes/winetricks; do
    [ -f "$winetricks" ] && tool=${winetricks%/protonfixes/winetricks} && break
  done
  [ -n "$tool" ] || { warn "No Proton with protonfixes/winetricks is installed; skipping the dinput verb."; return; }
  info "Running winetricks dinput with ${tool##*/}"
  wait_prefix_idle "$compatdata" 120
  run env WINEPREFIX="$compatdata/pfx" WINE="$tool/files/bin/wine" WINELOADER="$tool/files/bin/wine" \
    WINESERVER="$tool/files/bin/wineserver" PATH="$tool/protonfixes/files/bin:$tool/files/bin:$PATH" \
    bash "$winetricks" -q dinput || warn "winetricks dinput failed."
}

# Small files 7th Heaven and FF7 look for in the prefix.
prefix_extras() {
  local compatdata=$1 appid=$2 drive=$1/pfx/drive_c dir docs
  [ "$DRY_RUN" = 1 ] && return 0
  for dir in system32 syswow64; do
    [ -d "$drive/windows/$dir" ] && cp -f "$ASSETS_DIR/timeout.exe" "$drive/windows/$dir/timeout.exe"
  done
  if [ ${#CD_DRIVES[@]} -eq 0 ]; then
    [ -f "$drive/.windows-label" ] || echo FF7DISC1 > "$drive/.windows-label"
    [ -f "$drive/.windows-serial" ] || echo 44000000 > "$drive/.windows-serial"
  fi
  if [ "$appid" = "$FF7_STEAM_2013" ]; then
    for docs in "$drive"/users/steamuser/Documents "$drive"/users/steamuser/My\ Documents; do
      [ -d "$docs" ] || continue
      dir="$docs/Square Enix/FINAL FANTASY VII Steam"
      compgen -G "$dir/user_*" >/dev/null || mkdir -p "$dir/user_12345678"
      break
    done
  fi
}
