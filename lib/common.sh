# shellcheck shell=bash
# Logging, prompts, downloads and dry-run plumbing shared by every step.

APP_NAME=7thDroid
APP_ID=7thdroid
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}/$APP_ID
DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/$APP_ID
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID
LOG_FILE=$STATE_DIR/install.log
STATE_FILE=$DATA_DIR/install.env

ASSUME_YES=${ASSUME_YES:-0}
DRY_RUN=${DRY_RUN:-0}

if [ -t 1 ]; then
  C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RESET=$'\e[0m'
else
  C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_RESET=''
fi

start_log() {
  mkdir -p "$STATE_DIR"
  : > "$LOG_FILE"
  exec > >(tee -a "$LOG_FILE") 2>&1
}

step()  { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()  { printf '    %sWarning:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
debug() { printf '    %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >> "${LOG_FILE:-/dev/null}"; }
die()   { printf '\n%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Runs a command, or only prints it with --dry-run.
run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf '    %s[dry-run]%s' "$C_DIM" "$C_RESET"
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  debug "+ $(printf '%q ' "$@")"
  "$@"
}

# ask VAR "Question" [default]
ask() {
  local __var=$1 question=$2 default=${3:-} reply
  if [ "$ASSUME_YES" = 1 ]; then
    printf -v "$__var" '%s' "$default"
    info "$question ${default:+[$default]} (--yes)"
    return
  fi
  read -r -e -p "    $question${default:+ [$default]}: " reply || reply=
  printf -v "$__var" '%s' "${reply:-$default}"
}

# ask_yn "Question" y|n -> status 0 for yes
ask_yn() {
  local question=$1 default=${2:-y} reply hint
  [ "$default" = y ] && hint='Y/n' || hint='y/N'
  if [ "$ASSUME_YES" = 1 ]; then
    info "$question [$hint] (--yes: $default)"
    [ "$default" = y ]
    return
  fi
  while true; do
    read -r -p "    $question [$hint]: " reply || reply=
    case ${reply:-$default} in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
    esac
  done
}

# choose VAR "Question" option... -> VAR gets the 0-based index; the first option is the default.
choose() {
  local __var=$1 question=$2 i reply
  shift 2
  info "$question"
  i=1
  local option
  for option in "$@"; do
    info "  $i) $option"
    i=$((i + 1))
  done
  if [ "$ASSUME_YES" = 1 ] || [ $# -eq 1 ]; then
    printf -v "$__var" '%s' 0
    info "Using 1) $1"
    return
  fi
  while true; do
    read -r -p "    Choose 1-$#: [1] " reply || reply=
    reply=${reply:-1}
    if [[ $reply =~ ^[0-9]+$ ]] && [ "$reply" -ge 1 ] && [ "$reply" -le $# ]; then
      printf -v "$__var" '%s' $((reply - 1))
      return
    fi
  done
}

pause() {
  [ "$ASSUME_YES" = 1 ] && return
  read -r -p "    $* Press Enter to continue... " _ || true
}

# download URL [file name] -> prints the cached path
download() {
  local url=$1 name=${2:-${1##*/}} dest
  dest=$CACHE_DIR/$name
  mkdir -p "$CACHE_DIR"
  if [ -s "$dest" ]; then
    info "Using cached $name" >&2
  elif [ "$DRY_RUN" = 1 ]; then
    run curl -fL --retry 4 -o "$dest" "$url" >&2
  else
    info "Downloading $name" >&2
    curl -fL --retry 4 --retry-delay 2 --progress-bar -o "$dest.part" "$url" >&2 \
      || { rm -f "$dest.part"; die "Download failed: $url"; }
    mv "$dest.part" "$dest"
  fi
  printf '%s\n' "$dest"
}

# Linux path -> Wine Z: path
winpath() {
  local path=$1
  printf 'Z:%s\n' "${path//\//\\}"
}

python() { python3 -I "$@"; }

save_state() {
  mkdir -p "$DATA_DIR"
  local name
  {
    for name in "$@"; do
      printf '%s=%q\n' "$name" "${!name}"
    done
  } > "$STATE_FILE"
}

load_state() {
  [ -f "$STATE_FILE" ] || return 1
  # shellcheck disable=SC1090
  . "$STATE_FILE"
}
