# shellcheck shell=bash
# Getting, installing and configuring 7th Heaven.

SEVENTH_REPO=tsunamods-codes/7th-Heaven
SEVENTH_PINNED_TAG=4.5.2
SEVENTH_PINNED_FILE=7thHeaven-v4.5.2.0_Release.exe
SEVENTH_DIR_WIN='C:\7th Heaven'

# select_seventh_heaven -> SEVENTH_CHANNEL, SEVENTH_TAG, SEVENTH_URL, SEVENTH_FILE
select_seventh_heaven() {
  step "Choosing the 7th Heaven version"
  if [ -z "$SEVENTH_CHANNEL" ]; then
    local pick
    choose pick "Which 7th Heaven build?" \
      "Pinned $SEVENTH_PINNED_TAG (tested with $APP_NAME)" \
      "Latest stable release" \
      "Canary (newest development build)"
    SEVENTH_CHANNEL=$(printf 'pinned\nlatest\ncanary\n' | sed -n "$((pick + 1))p")
  fi
  case $SEVENTH_CHANNEL in
    pinned)
      SEVENTH_TAG=$SEVENTH_PINNED_TAG SEVENTH_FILE=$SEVENTH_PINNED_FILE
      SEVENTH_URL=https://github.com/$SEVENTH_REPO/releases/download/$SEVENTH_TAG/$SEVENTH_FILE ;;
    latest|canary)
      local api line
      [ "$SEVENTH_CHANNEL" = latest ] && api=releases/latest || api=releases/tags/canary
      line=$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$SEVENTH_REPO/$api" | python -c '
import json, re, sys
release = json.load(sys.stdin)
exes = [a for a in release.get("assets", []) if a["name"].lower().endswith(".exe")]
exes.sort(key=lambda a: (not re.search(r"_(release|canary)\.exe$", a["name"], re.I), a["name"]))
if exes:
    a = exes[0]
    stamp = re.sub(r"[^0-9]", "", a.get("updated_at", ""))[:12]
    print("\t".join((release.get("tag_name", ""), a["name"], a["browser_download_url"], stamp)))
') || true
      [ -n "$line" ] || die "Could not look up the $SEVENTH_CHANNEL 7th Heaven release on GitHub."
      IFS=$'\t' read -r SEVENTH_TAG SEVENTH_FILE SEVENTH_URL stamp <<< "$line"
      # canary keeps its tag and file name across builds; the asset date keeps cached copies apart
      [ "$SEVENTH_CHANNEL" = canary ] && SEVENTH_FILE=canary-$stamp-$SEVENTH_FILE ;;
    *) die "Unknown 7th Heaven version '$SEVENTH_CHANNEL' (use pinned, latest or canary)." ;;
  esac
  ok "7th Heaven $SEVENTH_TAG ($SEVENTH_CHANNEL)"
  SEVENTH_INSTALLER=$(download "$SEVENTH_URL" "$SEVENTH_FILE")
}

# The .NET Desktop channel each build is known to need. innoextract can't read 7th Heaven's
# installers (Inno Setup 6.5; DroidDeck's innoextract stops at 6.1), and builds other than the pinned
# one may change it, so check_seventh_dotnet confirms it from the installed app afterwards.
SEVENTH_PINNED_DOTNET=9.0
SEVENTH_CANARY_DOTNET=10.0

# The .NET Desktop channel the chosen build needs, without running its installer -> MAJOR.MINOR
seventh_dotnet_channel() {
  local tmp path channel=''
  if [ "$HAVE_INNOEXTRACT" = 1 ] && [ "$DRY_RUN" != 1 ]; then
    tmp=$(mktemp -d)
    path=$("$INNOEXTRACT" -l "$SEVENTH_INSTALLER" 2>/dev/null | grep -io '"[^"]*7th heaven\.runtimeconfig\.json"' | head -n1 | tr -d '"')
    if [ -n "$path" ] && "$INNOEXTRACT" -s -d "$tmp" -I "$path" "$SEVENTH_INSTALLER" >/dev/null 2>&1; then
      channel=$(runtimeconfig_channel "$(find "$tmp" -iname '*.runtimeconfig.json' | head -n1)")
    fi
    rm -rf -- "$tmp"
  fi
  if [ -z "$channel" ]; then
    case $SEVENTH_CHANNEL in
      canary) channel=$SEVENTH_CANARY_DOTNET ;;
      latest) [ "$SEVENTH_TAG" = "$SEVENTH_PINNED_TAG" ] && channel=$SEVENTH_PINNED_DOTNET || channel=$SEVENTH_CANARY_DOTNET ;;
      *) channel=$SEVENTH_PINNED_DOTNET ;;
    esac
    debug "7th Heaven $SEVENTH_TAG: .NET $channel from the known-build table"
  fi
  echo "$channel"
}

# check_seventh_dotnet COMPATDATA - read what the installed 7th Heaven asks for, and install it if it
# differs from what was installed before it.
check_seventh_dotnet() {
  local compatdata=$1 config channel
  [ "$DRY_RUN" = 1 ] && return 0
  config=$(find "$compatdata/pfx/drive_c/7th Heaven" -maxdepth 1 -iname '7th heaven.runtimeconfig.json' | head -n1)
  [ -n "$config" ] || { warn "7th Heaven has no runtimeconfig.json; could not confirm its .NET version."; return 0; }
  channel=$(runtimeconfig_channel "$config")
  [ -n "$channel" ] || { warn "Could not read the .NET version from $config."; return 0; }
  if dotnet_installed "$compatdata" x64 "$channel" && dotnet_installed "$compatdata" x86 "$channel"; then
    ok "7th Heaven $SEVENTH_TAG runs on .NET Desktop $channel, which is installed."
    return 0
  fi
  info "7th Heaven $SEVENTH_TAG asks for .NET Desktop $channel."
  install_dotnet "$compatdata" "$channel"
}

seventh_exe() { printf '%s\n' "$1/pfx/drive_c/7th Heaven/7th Heaven.exe"; }

install_seventh_heaven() {
  local compatdata=$1 exe
  exe=$(seventh_exe "$compatdata")
  if [ -f "$exe" ] && [ "$REINSTALL" != 1 ] \
     && ! ask_yn "7th Heaven is already installed in this prefix. Run its installer again (update or repair)?" n; then
    return 0
  fi
  info "Installing 7th Heaven to $SEVENTH_DIR_WIN. If 7th Heaven opens when it finishes, close it to continue."
  fex_run "$compatdata" "$SEVENTH_INSTALLER" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- \
    /DIR="$SEVENTH_DIR_WIN" /LOG="C:\\$APP_ID-7thHeaven-install.log" || warn "The 7th Heaven installer reported an error."
  [ "$DRY_RUN" = 1 ] || [ -f "$exe" ] \
    || die "7th Heaven did not install. Its log is $compatdata/pfx/drive_c/$APP_ID-7thHeaven-install.log"
  ok "7th Heaven installed."
}

# configure_seventh_heaven COMPATDATA GAME_EXE FF7_VERSION
configure_seventh_heaven() {
  local compatdata=$1 game_exe=$2 version=$3 workshop channel=Stable
  workshop=$compatdata/pfx/drive_c/7th\ Heaven/7thWorkshop
  [ "$SEVENTH_CHANNEL" = canary ] && channel=Canary
  info "Pointing 7th Heaven at $game_exe ($version)"
  [ "$DRY_RUN" = 1 ] && return 0
  mkdir -p "$workshop/profiles" "$compatdata/pfx/drive_c/7th Heaven/mods"
  python - "$ASSETS_DIR/settings.xml.in" "$workshop/settings.xml" "$(winpath "$game_exe")" "$version" \
    "$SEVENTH_DIR_WIN\\mods" "$channel" <<'EOF'
import os, re, sys
template, target, exe, version, library, channel = sys.argv[1:]
values = {"FF7Exe": exe, "FF7InstalledVersion": version}
if os.path.exists(target):
    with open(target, encoding="utf-8-sig") as f:
        text = f.read()
else:
    with open(template, encoding="utf-8") as f:
        text = f.read()
    values.update(LibraryLocation=library, FFNxUpdateChannel=channel, AppUpdateChannel=channel)
for tag, value in values.items():
    value = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if re.search(r"<%s>.*?</%s>|<%s\s*/>" % (tag, tag, tag), text, re.S):
        text = re.sub(r"<%s>.*?</%s>|<%s\s*/>" % (tag, tag, tag), lambda m: "<%s>%s</%s>" % (tag, value, tag), text, count=1, flags=re.S)
    else:
        text = text.replace("</Settings>", "  <%s>%s</%s>\n</Settings>" % (tag, value, tag))
with open(target, "w", encoding="utf-8") as f:
    f.write(text)
EOF
}
