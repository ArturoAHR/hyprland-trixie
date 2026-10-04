# shellcheck shell=bash disable=SC2034  # the C_* tables are read by the scripts that source this
# lib/common.sh - shared by the hyprland-trixie command (host) and the scripts that run in the build container.

REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
REC=share/hyprland-trixie   # inside every build: what's installed, from which pins, and the host's runtime packages

say()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------- configuration ----------
CONFIG_KEYS=(OPT_ROOT BIN_DIR CACHE_DIR IMAGE MODULES JOBS BUILD_TYPE AQ_DRM_DEVICES
             TERMINAL LAUNCHER QT_PLATFORM_THEME POLKIT_AGENT)
USER_CONFIG=${HYPRLAND_TRIXIE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/hyprland-trixie/config.env}

load_config() { # defaults < user config < environment
  local k
  local -A keep=()
  for k in "${CONFIG_KEYS[@]}"; do [[ -v $k ]] && keep[$k]=${!k}; done
  # shellcheck source=../config.defaults.env
  source "$REPO/config.defaults.env"
  # shellcheck disable=SC1090
  [[ -f $USER_CONFIG ]] && source "$USER_CONFIG"
  for k in "${!keep[@]}"; do printf -v "$k" '%s' "${keep[$k]}"; done
  return 0
}

# ---------- apps ----------
# An app is something installed as $OPT_ROOT/<app>/<version>: hyprland, quickshell.
load_app() {
  [[ -f $REPO/apps/$1.sh ]] || die "unknown app: $1"
  APP=$1
  # shellcheck disable=SC1090
  source "$REPO/apps/$1.sh"
}
pins_file() { printf '%s/pins/%s/%s.env\n' "$REPO" "$1" "$2"; }

# ---------- components ----------
# One file per component in components/. Variables describe it; optional functions build it.
declare -gA C_DESC=() C_APP=() C_KIND=() C_URL=() C_TAGS=() C_RESOLVE=() C_NEEDS=() C_PC=() C_LINKS=() \
            C_FLAKE=() C_MARKER=() C_SKIP=() PC2C=()
COMPONENTS=()
load_components() {
  local f name pc
  local -a fields
  for f in "$REPO"/components/*.sh; do
    name=$(basename "$f" .sh)
    # Read only the variables, in a subshell, so the build functions stay out of this shell.
    mapfile -t fields < <(
      desc='' app='' kind=lib url='' tags='^v[0-9]+\.[0-9]+\.[0-9]+$' resolve=compatible needs='' pc='' \
        links='' flake='' marker='' check_skip=''
      # shellcheck disable=SC1090
      source "$f"
      set -f   # one line per field: lists may span lines in the file
      for x in "$desc" "$app" "$kind" "$url" "$tags" "$resolve" "$needs" "$pc" "$links" "$flake" "$marker" \
               "$check_skip"; do
        # shellcheck disable=SC2086
        set -- $x; printf '%s\n' "$*"
      done
    )
    COMPONENTS+=("$name")
    C_DESC[$name]=${fields[0]} C_APP[$name]=${fields[1]} C_KIND[$name]=${fields[2]} C_URL[$name]=${fields[3]} C_TAGS[$name]=${fields[4]}
    C_RESOLVE[$name]=${fields[5]} C_NEEDS[$name]=${fields[6]} C_PC[$name]=${fields[7]} C_LINKS[$name]=${fields[8]}
    C_FLAKE[$name]=${fields[9]:-$name} C_MARKER[$name]=${fields[10]} C_SKIP[$name]=${fields[11]}
    for pc in ${fields[7]}; do PC2C[$pc]=$name; done
  done
}
is_module() { [[ ${C_KIND[$1]:-} == module && ${C_APP[$1]} == "$APP" ]]; }
app_modules() { local c; for c in "${COMPONENTS[@]}"; do is_module "$c" && printf '%s\n' "$c"; done; return 0; }

# build_order <component...>: those components plus everything they need, dependencies first
build_order() {
  local -A state=()
  local -a out=()
  local c
  _visit() {
    local n
    case ${state[$1]:-} in visited) return ;; active) die "dependency cycle through $1" ;; esac
    [[ -n ${C_KIND[$1]:-} ]] || die "unknown component: $1"
    state[$1]=active
    for n in ${C_NEEDS[$1]}; do _visit "$n"; done
    state[$1]=visited
    out+=("$1")
  }
  for c in "$@"; do _visit "$c"; done
  printf '%s\n' "${out[@]}"
}

# ---------- pins and install records (both name=value files) ----------
declare -gA PIN=() INST=()
read_kv() { # read_kv <file> <assoc-name>: comments, blank lines and spaces ignored
  local -n _kv=$2
  local line
  _kv=()
  [[ -f $1 ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line//[[:space:]]/}
    [[ -z $line ]] && continue
    [[ $line == *=* ]] || die "$1: can't read line: $line"
    _kv[${line%%=*}]=${line#*=}
  done < "$1"
}
read_pins() { read_kv "$1" PIN; }
read_installed() { read_kv "$1/$REC/installed" INST; }

fetch() { # fetch <name> <release> <git-url> -> source folder, shared by every version that pins this release
  local d=$CACHE_DIR/src/$1-$2
  if [[ ! -d $d ]]; then
    mkdir -p "$CACHE_DIR/src"
    rm -rf "$d.part"
    git -c advice.detachedHead=false clone -q --depth=1 --branch "$2" --recurse-submodules --shallow-submodules \
      "$3" "$d.part" >&2
    mv "$d.part" "$d"
  fi
  printf '%s\n' "$d"
}

tag_version() { sed -E 's/^[^0-9]*//' <<<"$1"; }   # v0.14.2 -> 0.14.2, xkbcommon-1.13.2 -> 1.13.2
ver_ge() { [[ $(printf '%s\n' "$1" "$2" | sort -V | head -n1) == "$2" ]]; }   # $1 >= $2

auto_jobs() { # one job per CPU, capped at one per 2 GB of available RAM (C++26 units are heavy)
  local mem; mem=$(( $(awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo) / 2 ))
  (( mem < 1 )) && mem=1
  (( mem < $(nproc) )) && printf '%s\n' "$mem" || nproc
}
