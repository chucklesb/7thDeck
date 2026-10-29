# shellcheck shell=bash
# FINAL FANTASY VII from a path the user gives: an installed folder, a GOG installer, or the 1998 CD-ROM
# release as disc images or copied disc folders.
#
# manual_source sets SOURCE_KIND and, depending on it:
#   folder      GAME_DIR, GAME_EXE
#   gog-setup   GOG_SETUP (and GAME_DIR once unpacked)
#   cd          CD_DISCS (folders, disc 1 first)

FF7_CD_LABELS=(FF7DISC1 FF7DISC2 FF7DISC3)

is_iso() { [[ ${1,,} == *.iso ]]; }
is_exe() { [[ ${1,,} == *.exe ]]; }

# A folder holding a 1998 disc: its root has an installer and an FF7 data folder.
is_cd_folder() {
  local dir=$1
  compgen -G "$dir/[Ss][Ee][Tt][Uu][Pp].[Ee][Xx][Ee]" >/dev/null \
    || compgen -G "$dir/[Ff][Ff]7*/" >/dev/null
}

# pick_source ARRAY - the same choices as a typed path, with a file picker that starts in Downloads.
pick_source() {
  local -n __paths=$1
  local kind reply
  choose kind "Where is your copy of FINAL FANTASY VII?" \
    "An installed game folder (copied from a PC or another launcher)" \
    "A GOG installer (setup_final_fantasy_vii_....exe)" \
    "1998 CD-ROM disc images (.iso)" \
    "Folders copied from the 1998 CD-ROMs"
  case $kind in
    0) ui_paths reply "Choose the folder that holds FF7's .exe" folder ;;
    1) ui_paths reply "Choose the GOG installer" file "GOG installer | *.exe *.EXE" ;;
    2) ui_paths reply "Choose the disc images (select all discs)" files "Disc images | *.iso *.ISO" ;;
    3) ui_paths reply "Choose the disc folders (select all discs)" folders ;;
  esac
  mapfile -t __paths <<< "$reply"
  [ -n "${__paths[0]:-}" ] || __paths=()
}

manual_source() {
  local paths=("$@") path exe isos=() dirs=()
  while [ ${#paths[@]} -eq 0 ]; do
    if [ "$UI_MODE" = zenity ] && [ "$ASSUME_YES" != 1 ]; then
      pick_source paths
      continue
    fi
    info "No installed copy of FINAL FANTASY VII was found automatically."
    info "Enter the path to one of the following (Android's Downloads folder is /root/Storage/Download):"
    info "  - an installed FF7 folder (from a PC, a store, etc.)"
    info "  - a GOG installer (setup_final_fantasy_vii_*.exe)"
    info "  - 1998 CD-ROM images (.iso), a folder of them, or folders copied from the discs"
    local reply
    ask reply "Path(s), separated by spaces if more than one (quote paths with spaces)"
    [ -n "$reply" ] || { [ "$ASSUME_YES" = 1 ] && die "No game source given (use --source)."; continue; }
    eval "paths=($reply)" 2>/dev/null || { warn "Could not read that; check the quoting."; paths=(); }
  done

  for path in "${paths[@]}"; do
    path=${path/#\~/$HOME}
    [ -e "$path" ] || die "$path does not exist."
    path=$(readlink -f "$path")
    if [ -d "$path" ]; then
      if exe=$(find_game_exe "$path") && [ -n "$exe" ]; then
        SOURCE_KIND=folder GAME_EXE=$exe GAME_DIR=${exe%/*}
        return
      fi
      if is_cd_folder "$path"; then
        dirs+=("$path")
        continue
      fi
      local iso
      while IFS= read -r iso; do isos+=("$iso"); done < <(find "$path" -maxdepth 1 -type f -iname '*.iso' | sort)
      [ ${#isos[@]} -gt 0 ] || die "$path has no FF7 executable, disc images or disc contents."
    elif is_iso "$path"; then
      isos+=("$path")
    elif is_exe "$path"; then
      SOURCE_KIND=gog-setup GOG_SETUP=$path
      return
    else
      die "$path is not a folder, a disc image or an installer."
    fi
  done

  if [ ${#isos[@]} -gt 0 ]; then
    [ "$HAVE_7Z" = 1 ] || die "Unpacking .iso files needs DroidDeck's 7z ($MSITOOLS_DIR/7z). Extract the discs to folders and give those instead."
    local i=1 iso dest
    for iso in "${isos[@]}"; do
      dest=$DATA_DIR/cd/disc$i
      if [ -d "$dest" ] && [ "$(cat "$dest/.$APP_ID-source" 2>/dev/null)" = "$iso" ]; then
        info "Disc $i already unpacked."
      else
        info "Unpacking ${iso##*/} (disc $i)"
        run rm -rf "$dest"
        run mkdir -p "$dest"
        run sevenzip x -y -o"$dest" "$iso" >/dev/null || die "Could not unpack $iso."
        [ "$DRY_RUN" = 1 ] || printf '%s\n' "$iso" > "$dest/.$APP_ID-source"
      fi
      dirs+=("$dest")
      i=$((i + 1))
    done
  fi
  [ ${#dirs[@]} -le 3 ] || die "FF7 has three discs; ${#dirs[@]} were given."
  SOURCE_KIND=cd CD_DISCS=("${dirs[@]}")
}

# The GOG installer is InnoSetup: innoextract unpacks it without Wine, and so without the FEX x87
# problem. Running it is the fallback; that needs the prefix, so it happens in install_pending_game.
unpack_gog_setup() {
  local exe
  ask GAME_DIR "Folder to put the game in" "${GAME_DIR:-$HOME/Games/FINAL FANTASY VII}"
  [ -n "$GAME_DIR" ] || die "No folder given."
  GAME_DIR=${GAME_DIR/#\~/$HOME}
  if exe=$(find_game_exe "$GAME_DIR" 2>/dev/null) && [ -n "$exe" ]; then
    info "The game is already in $GAME_DIR."
    GAME_EXE=$exe
    SOURCE_KIND=folder
    return 0
  fi
  [ "$HAVE_INNOEXTRACT" = 1 ] || return 1
  local staging=$GAME_DIR.$APP_ID-unpack
  info "Unpacking ${GOG_SETUP##*/} with innoextract"
  run rm -rf "$staging"
  run mkdir -p "$staging"
  if ! run "$INNOEXTRACT" --gog --exclude-temp --silent --progress -d "$staging" "$GOG_SETUP"; then
    warn "innoextract could not unpack this installer; it will be run instead."
    run rm -rf "$staging"
    return 1
  fi
  run mkdir -p "$GAME_DIR"
  if [ "$DRY_RUN" != 1 ]; then
    local from=$staging
    [ -d "$staging/app" ] && from=$staging/app
    cp -a "$from"/. "$GAME_DIR"/ || die "Could not copy the game into $GAME_DIR."
    rm -rf "$staging"
    GAME_EXE=$(find_game_exe "$GAME_DIR")
    [ -n "$GAME_EXE" ] || { warn "The unpacked files have no FF7 executable; the installer will be run instead."; return 1; }
  else
    GAME_EXE=$GAME_DIR/FFVII.exe
  fi
  SOURCE_KIND=folder
  ok "Unpacked to $GAME_DIR"
}

# Wine CD drives for the discs: d:, e:, f:, each with the label FF7 checks for.
map_cd_drives() {
  local compatdata=$1 i letters=(d e f) disc drive entry
  CD_DRIVES=()
  for i in "${!CD_DISCS[@]}"; do
    disc=${CD_DISCS[$i]}
    drive=$disc
    # A folder the user gave is never written to: the drive is a folder of links to its contents,
    # which can carry the label. Discs 7thDroid unpacked itself get the label directly.
    if [[ $disc != "$DATA_DIR/cd/"* ]]; then
      drive=$DATA_DIR/cd/drive$((i + 1))
      if [ "$DRY_RUN" != 1 ]; then
        rm -rf -- "$drive"
        mkdir -p "$drive"
        for entry in "$disc"/* "$disc"/.[!.]*; do
          [ -e "$entry" ] || continue
          case ${entry##*/} in .windows-label|.windows-serial) continue ;; esac
          ln -s "$entry" "$drive/${entry##*/}"
        done
      fi
      CD_DISCS[$i]=$drive
    fi
    run ln -sfn "$drive" "$compatdata/pfx/dosdevices/${letters[$i]}:"
    [ "$DRY_RUN" = 1 ] || {
      printf '%s\n' "${FF7_CD_LABELS[$i]}" > "$drive/.windows-label"
      printf '%s\n' "4400000$i" > "$drive/.windows-serial"
    }
    CD_DRIVES+=("${letters[$i]}:")
  done
}

# Runs whatever installer the source still needs, now that the prefix exists.
install_pending_game() {
  local compatdata=$1 setup
  case $SOURCE_KIND in
    gog-setup)
      info "Running the GOG installer. Accept the defaults, or install anywhere you like."
      fex_run "$compatdata" "$GOG_SETUP" /DIR="$(winpath "$GAME_DIR")" \
        || warn "The installer reported an error."
      ;;
    cd)
      setup=$(find -L "${CD_DISCS[0]}" -maxdepth 1 -type f \( -iname 'setup.exe' -o -iname 'install.exe' \) | head -n1)
      [ -n "$setup" ] || die "Disc 1 has no setup.exe."
      info "Running the CD installer from drive d:. Choose a full install if it asks."
      fex_run "$compatdata" "$setup" || warn "The installer reported an error."
      GAME_DIR=$compatdata/pfx/drive_c
      ;;
    *) return 0 ;;
  esac
  [ "$DRY_RUN" = 1 ] && { GAME_EXE=$GAME_DIR/FFVII.exe; return; }
  GAME_EXE=$(find_game_exe "$GAME_DIR")
  [ -n "$GAME_EXE" ] || die "The installer finished, but no FF7 executable was found in $GAME_DIR."
  GAME_DIR=${GAME_EXE%/*}
  ok "FINAL FANTASY VII installed at $GAME_DIR"
}
