#!/usr/bin/env bash
# lib/resolve.sh - works out pins, and what the image lacks. Runs INSIDE the build container.
#   resolve.sh pin   <app> <version|latest>        prints a pins file for that version
#   resolve.sh add   <app> <version> <component...> prints pins lines for components the version's file lacks
#   resolve.sh check <app> <version> <component...> prints what the image lacks to build those
# Results go to stdout, progress to stderr.
set -Eeuo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "$REPO/lib/common.sh"
load_config
load_components

GIT=$CACHE_DIR/git
declare -A FRESH=() REASON=()
log() { printf '%s\n' "$*" >&2; }
has() { [[ " $1 " == *" $2 "* ]]; }   # has <list> <word>

# ---------- git: bare treeless mirrors (commits and tags only; files are fetched when read) ----------
git_dir() { printf '%s/%s.git\n' "$GIT" "$1"; }
refresh() { # once per run; call it directly, not in $(...), so FRESH sticks
  local c=$1 d
  d=$(git_dir "$c")
  [[ -n ${FRESH[$c]:-} ]] && return 0
  mkdir -p "$GIT"
  if [[ -d $d ]]; then
    git -C "$d" fetch -q --prune origin '+refs/heads/*:refs/heads/*' '+refs/tags/*:refs/tags/*' >&2
  else
    log "   fetching $c history"
    git clone -q --bare --filter=tree:0 "${C_URL[$c]}" "$d" >&2
  fi
  FRESH[$c]=1
}
sort_tags() { # tags on stdin -> "version tag" lines, oldest first
  local t
  while read -r t; do printf '%s %s\n' "$(tag_version "$t")" "$t"; done | sort -V -k1,1
}
releases() { # releases <component> -> "version tag" lines, oldest first
  git -C "$(git_dir "$1")" tag -l | { grep -E "${C_TAGS[$1]}" || true; } | sort_tags
}
newest_in_series() { # newest_in_series <component> <x.y> -> newest x.y.* tag
  releases "$1" | awk -v s="$2." 'index($1, s) == 1 {t = $2} END {print t}'
}

# ---------- requirements, read from CMakeLists.txt ----------
parse_requirements() { # CMake text on stdin -> "pc|cmake name minimum" lines (minimum may be empty)
  local text blocks k v b name spec rest
  local -A var=()
  text=$(sed 's/#.*//')
  # set(...) and pkg_check_modules(...) calls, each joined onto one line, with quotes and the spaces around
  # comparisons dropped: set(DEPS "foo >= ${FOO_MIN}" bar) -> set(DEPS foo>=${FOO_MIN} bar)
  blocks=$(awk '/(^|[^A-Za-z_])(set|pkg_check_modules)[[:space:]]*\(/ {f = 1; b = ""}
                f {b = b " " $0} f && /\)/ {print b; f = 0}' <<<"$text" |
    sed -E 's/"/ /g; s/[[:space:]]*(>=|<=|=|<|>)[[:space:]]*/\1/g')
  while IFS= read -r b; do
    [[ $b == *pkg_check_modules* || $b != *set\(* ]] && continue
    b=${b#*set(}; b=${b%%)*}
    read -r k rest <<<"$b"
    [[ -n $k ]] && var[$k]=$rest
  done <<<"$blocks"
  # pkg_check_modules(<prefix> REQUIRED ... <module>[>=version] ...): only the REQUIRED ones. Lists and
  # versions kept in variables (pkg_check_modules(deps REQUIRED ${PUBLIC_PKG_DEPS})) are expanded.
  grep 'pkg_check_modules' <<<"$blocks" |
    while IFS= read -r b; do
      b=${b#*pkg_check_modules}; b=${b#*(}; b=${b%%)*}
      for _ in 1 2; do   # twice: a list can hold versions kept in other variables
        for k in "${!var[@]}"; do [[ $b == *"\${$k}"* ]] && b=${b//"\${$k}"/ ${var[$k]} }; done
      done
      b=$(sed -E 's/[[:space:]]*(>=|<=|=|<|>)[[:space:]]*/\1/g' <<<"$b")
      has "$b" REQUIRED || continue
      set -f
      # shellcheck disable=SC2086
      set -- $b
      set +f
      shift   # the variable prefix
      for spec; do
        case $spec in REQUIRED | QUIET | IMPORTED_TARGET | GLOBAL | NO_CMAKE_PATH | NO_CMAKE_ENVIRONMENT_PATH) continue ;; esac
        [[ $spec == \$* ]] && continue
        name=${spec%%[<>=]*} v=
        [[ $spec == *'>='* ]] && v=${spec#*>=}
        [[ $v =~ ^[0-9][0-9.]*$ ]] || v=
        printf 'pc %s %s\n' "$name" "$v"
      done
    done
  # find_package(<name> <version> ...)
  sed -nE 's/.*find_package\([[:space:]]*([A-Za-z0-9_-]+)[[:space:]]+([0-9][0-9.]*).*/cmake \1 \2/p' <<<"$text"
}
requirements() { # requirements <component> <tag>: from its top-level CMakeLists.txt, via the mirror
  local text
  text=$(git -C "$(git_dir "$1")" show "$2:CMakeLists.txt" 2>/dev/null) || return 0
  parse_requirements <<<"$text"
}
pinned_version() { # pinned_version <component> -> the version its pin stands for (empty if unpinned)
  local p=${PIN[$1]:-}
  case $p in
    '') ;;
    system) pkg-config --modversion "${C_PC[$1]%% *}" 2>/dev/null || true ;;
    *) tag_version "$p" ;;
  esac
}

# ---------- policies: each sets PIN[c] and REASON[c] ----------
pick_self() { # the app's own release: <version> or latest
  local c=$APP_ROOT line
  refresh "$c"
  if [[ $1 == latest ]]; then line=$(releases "$c" | tail -n1)
  else line=$(releases "$c" | awk -v v="$1" '$1 == v' | tail -n1)
  fi
  [[ -n $line ]] || die "$c has no release ${1}"
  PIN[$c]=${line#* } VERSION=${line%% *} REASON[$c]="the version"
}
pick_newest() { # pick_newest <component> [why] [minimum]
  local c=$1 why=${2:-} min=${3:-} line
  refresh "$c"
  line=$(releases "$c" | tail -n1)
  [[ -n $line ]] || die "$c: no release tags match ${C_TAGS[$c]}"
  [[ -z $min ]] || ver_ge "${line%% *}" "$min" || die "$c: newest release ${line#* } is older than the $min required"
  PIN[$c]=${line#* } REASON[$c]="newest release${why:+; $why}"
}
flake_rev() { # the commit Hyprland's flake.lock pins for <component>, if any
  [[ -n $FLAKE ]] || return 0
  jq -r --arg n "${C_FLAKE[$1]}" '
    ((.nodes.root.inputs[$n] | if type == "string" then . else null end) // $n) as $k
    | .nodes[$k].locked.rev // empty' <<<"$FLAKE"
}
pick_flake() { # first release containing the commit upstream tests, then the newest patch release of that series
  local c=$1 d rev first pick series
  refresh "$c"
  d=$(git_dir "$c")
  rev=$(flake_rev "$c")
  if [[ -z $rev ]]; then pick_newest "$c" "not in Hyprland's flake.lock"; return; fi
  git -C "$d" cat-file -e "$rev^{commit}" 2>/dev/null || git -C "$d" fetch -q origin "$rev" >&2 || true
  first=$(git -C "$d" tag --contains "$rev" 2>/dev/null | { grep -E "${C_TAGS[$c]}" || true; } | sort_tags | head -n1)
  if [[ -n $first ]]; then
    series=${first%% *}
    series=${series%.*}
    pick=$(newest_in_series "$c" "$series")
    PIN[$c]=$pick REASON[$c]="Hyprland's flake.lock tests a commit first released in ${first#* }; newest $series.x"
  else
    pick=$(git -C "$d" tag --merged "$rev" | { grep -E "${C_TAGS[$c]}" || true; } | sort_tags | tail -n1)
    [[ -n $pick ]] || die "$c: no release at or before $rev"
    PIN[$c]=${pick#* } REASON[$c]="newest release before the commit Hyprland's flake.lock tests"
  fi
}
min_required() { # the highest minimum any pinned component declares for <component>
  local c=$1 r kind name v min=
  for r in "${!PIN[@]}"; do
    [[ ${PIN[$r]} == system || -z ${C_URL[$r]:-} ]] && continue
    while read -r kind name v; do
      [[ ${PC2C[$name]:-} == "$c" && -n $v ]] || continue
      if [[ -z $min ]] || ! ver_ge "$min" "$v"; then min=$v; fi
    done < <(requirements "$r" "${PIN[$r]}")
  done
  printf '%s\n' "$min"
}
pick_system_or_newest() { # Debian's copy when it's new enough, otherwise the newest release
  local c=$1 min sys
  min=$(min_required "$c")
  sys=$(pkg-config --modversion "${C_PC[$c]%% *}" 2>/dev/null || true)
  if has "$APP_NEWEST" "$c"; then
    pick_newest "$c" "${sys:+Debian has $sys, and }$APP takes the newest" "$min"
  elif [[ -n $sys ]] && { [[ -z $min ]] || ver_ge "$sys" "$min"; }; then
    PIN[$c]=system REASON[$c]="Debian's $sys${min:+ meets >= $min}"
  else
    pick_newest "$c" "${sys:+Debian has $sys}${min:+${sys:+, }needs >= $min}" "$min"
  fi
}
pick_lua() { # the series Hyprland asks for, newest release, checksum from lua.org
  local text series line
  text=$(git -C "$(git_dir "$APP_ROOT")" show "${PIN[$APP_ROOT]}:CMakeLists.txt")
  series=$(grep -oE 'lua *>= *[0-9]+\.[0-9]+' <<<"$text" | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || true)
  series=${series:-5.5}
  line=$(curl -fsSL https://www.lua.org/ftp/ \
    | awk -F'"' '/CLASS="name"/ && /HREF="lua-[0-9.]+\.tar\.gz"/ {n = $4}
                 /CLASS="sum"/ && n != "" {s = $0; gsub(/.*CLASS="sum">|<\/TD>.*/, "", s); print n, s; n = ""}' \
    | sed -E 's/^lua-([0-9.]+)\.tar\.gz /\1 /' | awk -v s="$series." 'index($1, s) == 1' | sort -V -k1,1 | tail -n1)
  [[ -n $line ]] || die "lua: no $series.x release listed on lua.org"
  PIN["lua"]=${line%% *} PIN["lua.sha256"]=${line#* }
  REASON[lua]="newest Lua $series.x on lua.org (Hyprland asks for lua >= $series)"
}
raise_to() { # raise_to <component> <minimum> <why>: first release >= minimum, newest patch of its series
  local v t first=
  while read -r v t; do ver_ge "$v" "$2" && { first=$v; break; }; done < <(releases "$1")
  [[ -n $first ]] || die "$1: no release >= $2 ($3)"
  PIN[$1]=$(newest_in_series "$1" "${first%.*}") REASON[$1]="raised to >= $2: $3"
}
raise_pass() { # make every pinned component meet the minimums the others declare
  local round r kind name min dep have changed
  for round in 1 2 3 4 5; do
    changed=
    for r in "$@"; do
      [[ -n ${PIN[$r]:-} && ${PIN[$r]} != system && -n ${C_URL[$r]} ]] || continue
      while read -r kind name min; do
        dep=${PC2C[$name]:-}
        [[ -n $dep && -n $min && -n ${PIN[$dep]:-} && $dep != "$r" ]] || continue
        have=$(pinned_version "$dep")
        [[ -z $have ]] || ver_ge "$have" "$min" && continue
        if [[ ${PIN[$dep]} == system ]]; then pick_newest "$dep" "Debian's $have is older than $r needs ($min)" "$min"
        else raise_to "$dep" "$min" "$r ${PIN[$r]} needs $name >= $min"
        fi
        log "   $dep -> ${PIN[$dep]} (${REASON[$dep]})"
        changed=1
      done < <(requirements "$r" "${PIN[$r]}")
    done
    [[ -z $changed ]] && return 0
    log "   (round $round changed pins; checking again)"
  done
  die "pins didn't settle after 5 rounds"
}
pick_compatible() { # newest release whose declared minimums the current pins meet
  local c=$1 v t ok why kind name min dep have skipped='' n=0
  refresh "$c"
  while read -r v t; do
    n=$((n + 1))
    (( n > 20 )) && break
    ok=1 why=
    while read -r kind name min; do
      [[ -n $min ]] || continue
      dep=${PC2C[$name]:-}
      if [[ -n $dep ]]; then have=$(pinned_version "$dep")
      elif [[ $kind == pc ]]; then have=$(pkg-config --modversion "$name" 2>/dev/null || true)
      else continue
      fi
      [[ -z $have ]] || ver_ge "$have" "$min" || { ok='' why="$name $have < $min"; break; }
    done < <(requirements "$c" "$t")
    if [[ -n $ok ]]; then
      PIN[$c]=$t REASON[$c]="newest release these pins satisfy${skipped:+; not $skipped}"
      return 0
    fi
    skipped+="${skipped:+, }$t ($why)"
  done < <(releases "$c" | sort -V -r -k1,1)
  REASON[$c]="no release fits these pins${skipped:+: $skipped}"
  return 1
}

resolve() { # resolve <component...>: pin the given components that aren't pinned yet, in order
  local c todo=()
  for c in "$@"; do [[ -z ${PIN[$c]:-} && ${C_RESOLVE[$c]} != none ]] && todo+=("$c"); done
  for c in "${todo[@]}"; do
    case ${C_RESOLVE[$c]} in
      flake) log "== $c"; pick_flake "$c" ;;
      newest) log "== $c"; pick_newest "$c" ;;
      lua) log "== $c"; pick_lua ;;
    esac
  done
  for c in "${todo[@]}"; do
    [[ ${C_RESOLVE[$c]} == system-or-newest ]] && { log "== $c"; pick_system_or_newest "$c"; }
  done
  log "== checking that the pins meet each other's minimums"
  raise_pass "$@"
  for c in "${todo[@]}"; do
    [[ ${C_RESOLVE[$c]} == compatible ]] || continue
    log "== $c"
    pick_compatible "$c" || log "   none: ${REASON[$c]}"
  done
  for c in "${todo[@]}"; do [[ -n ${PIN[$c]:-} ]] && log "   $c=${PIN[$c]}"; done
  return 0
}

pin_line() { # pin_line <component>
  local c=$1
  if [[ -n ${PIN[$c]:-} ]]; then
    printf '%-34s # %s\n' "$c=${PIN[$c]}" "${REASON[$c]:-}"
    [[ $c == lua ]] && printf '%s\n' "lua.sha256=${PIN[lua.sha256]}"
  else
    printf '# %s: %s\n' "$c" "${REASON[$c]:-not pinned}"
  fi
  return 0
}
load_flake() {
  FLAKE=
  [[ $APP_ROOT == hyprland ]] || return 0
  FLAKE=$(git -C "$(git_dir hyprland)" show "${PIN[hyprland]}:flake.lock" 2>/dev/null || true)
}

# ---------- commands ----------
cmd_pin() { # cmd_pin <version|latest>
  local all c
  # shellcheck disable=SC2046,SC2086
  all=$(build_order $APP_CORE $(app_modules)) || exit 1
  local -a ALL; mapfile -t ALL <<<"$all"
  PIN=()
  log "== $APP_ROOT"
  pick_self "$1"
  load_flake
  resolve "${ALL[@]}"
  printf '# Pins for %s %s, written by `hyprland-trixie pin` on %s.\n' "$APP" "$VERSION" "$(date +%F)"
  printf '# name=release, one per component; "system" means Debian'"'"'s own copy. Edit to override:\n'
  printf '# builds use exactly what is here.\n'
  for c in "${ALL[@]}"; do [[ ${C_KIND[$c]} == module || ${C_RESOLVE[$c]} == none ]] || pin_line "$c"; done
  if [[ -n $(app_modules) ]]; then
    printf '\n# Optional modules (hyprland-trixie modules)\n'
    for c in "${ALL[@]}"; do [[ ${C_KIND[$c]} == module ]] && pin_line "$c"; done
  fi
  return 0
}

cmd_add() { # cmd_add <version> <component...>: lines for components (and what they need) the pins lack
  local f order c new=()
  f=$(pins_file "$APP" "$1")
  shift
  read_pins "$f"
  VERSION=$(tag_version "${PIN[$APP_ROOT]}")
  refresh "$APP_ROOT"
  load_flake
  order=$(build_order "$@") || exit 1
  local -a ORD; mapfile -t ORD <<<"$order"
  for c in "${ORD[@]}"; do [[ -z ${PIN[$c]:-} && ${C_RESOLVE[$c]} != none ]] && new+=("$c"); done
  (( ${#new[@]} )) || return 0
  # mirrors for what's already pinned, so the minimum checks can read their requirements
  for c in "${!PIN[@]}"; do [[ -n ${C_URL[$c]:-} ]] && refresh "$c"; done
  resolve "${ORD[@]}"
  printf '\n# Added by `hyprland-trixie pin --add` on %s\n' "$(date +%F)"
  for c in "${new[@]}"; do pin_line "$c"; done
}

cmd_check() { # cmd_check <version> <component...>: what the image lacks to build those components
  local f order c tag src cm_file kind name min dep have d
  f=$(pins_file "$APP" "$1")
  shift
  read_pins "$f"
  for c in "$@"; do
    tag=${PIN[$c]:-}
    [[ -n $tag && $tag != system && -n ${C_URL[$c]} ]] || continue
    src=$(fetch "$c" "$tag" "${C_URL[$c]}")
    local -a prune=(-path "$src/.git" -o -path "$src/subprojects" -o -name tests -o -name test)
    for d in ${C_SKIP[$c]}; do prune+=(-o -path "$src/$d"); done
    local closure
    closure=" $(build_order "$c" | tr '\n' ' ') "
    while IFS= read -r cm_file; do
      while read -r kind name min; do
        dep=${PC2C[$name]:-}
        if [[ -n $dep ]]; then
          [[ $closure == *" $dep "* ]] || printf 'needs %s %s\n' "$c" "$dep"
        elif [[ $kind == pc ]]; then
          if ! pkg-config --exists "$name" 2>/dev/null; then printf 'missing %s %s\n' "$name" "$c"
          elif [[ -n $min ]]; then
            have=$(pkg-config --modversion "$name")
            ver_ge "$have" "$min" || printf 'old %s %s %s %s\n' "$name" "$have" "$min" "$c"
          fi
        fi
      done < <(parse_requirements < "$cm_file")
    done < <(find "$src" \( "${prune[@]}" \) -prune -o -name CMakeLists.txt -print)
  done | sort -u
}

[[ $# -ge 3 ]] || die "usage: resolve.sh pin|add|check <app> <version> [...]"
cmd=$1
load_app "$2"
shift 2
case $cmd in
  pin) cmd_pin "$1" ;;
  add) cmd_add "$@" ;;
  check) cmd_check "$@" ;;
  *) die "unknown: $cmd" ;;
esac
