#!/usr/bin/env bash
# lib/build.sh [--adopt] <app> <version> [module...]
# Runs INSIDE the build container; `hyprland-trixie build` and `hyprland-trixie adopt` start it.
# Builds <app> <version> into $OPT_ROOT/<app>/<version> from pins/<app>/<version>.env. A component already
# installed there with the same release is skipped, so adding a module to an old version builds only that module.
set -Eeuo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=common.sh
source "$REPO/lib/common.sh"
load_config
load_components

ADOPT=
[[ ${1:-} == --adopt ]] && { ADOPT=1; shift; }
load_app "${1:?usage: build.sh [--adopt] <app> <version> [module...]}"
VERSION=${2:?version}
shift 2
PINS=$(pins_file "$APP" "$VERSION")
[[ -f $PINS ]] || die "no pins for $APP $VERSION ($PINS)"
read_pins "$PINS"

PREFIX=$OPT_ROOT/$APP/$VERSION
SRC=$CACHE_DIR/src                       # sources, one per release, shared by every version that pins it
BLD=$CACHE_DIR/build/$APP/$VERSION       # build folders, one set per version, kept until `prune`
LOGS=$CACHE_DIR/logs/$APP/$VERSION
JOBS=${JOBS:-$(auto_jobs)}
export CC=$APP_CC CXX=$APP_CXX
export PATH="$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CMAKE_PREFIX_PATH="$PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
# DT_RPATH, not RUNPATH: it also covers the libraries' own dependencies, so all of them resolve from the build
export LDFLAGS="-Wl,--disable-new-dtags -Wl,-rpath,$PREFIX/lib"

mkdir -p "$SRC" "$BLD" "$LOGS" "$PREFIX/lib/pkgconfig" "$PREFIX/$REC/files"
exec 9>"$BLD/.lock"
flock -n 9 || die "another build of $APP $VERSION is running"
read_installed "$PREFIX"

# ---------- helpers for components/*.sh (they run with S=source, B=build folder, TAG, FILES set) ----------
# A build folder is reused only for the same install folder, build type and component file; anything else
# (say, a configure option added to components/<name>.sh after a failure) configures it afresh.
configured() { [[ -f $B/build.ninja && $(cat "$B/.hyprland-trixie" 2>/dev/null) == "$PREFIX $BUILD_TYPE $CSUM" ]]; }
stamp() { printf '%s\n' "$PREFIX $BUILD_TYPE $CSUM" > "$B/.hyprland-trixie"; }

# shellcheck disable=SC2120  # components pass arguments
cm() { # cm [extra cmake args]: configure once (delete the build folder to redo it), then build and install
  local a=() l
  # Debian's older libinput and xkbcommon are in the image too (Qt's -dev packages pull them in), and CMake's
  # pkg-config lookup can link those instead of the copies in the build whose headers it compiled against.
  for l in input xkbcommon; do
    [[ -e $PREFIX/lib/lib$l.so ]] && a+=("-Dpkgcfg_lib_deps_$l=$PREFIX/lib/lib$l.so")
  done
  if ! configured; then
    rm -rf "$B"
    cmake -S "$S" -B "$B" -G Ninja -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
      -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_RPATH="$PREFIX/lib" -DBUILD_TESTING=OFF "${a[@]}" "$@"
    stamp
  fi
  cmake --build "$B" -j "$JOBS"
  cmake --install "$B"
  sed '$a\' "$B/install_manifest.txt" > "$FILES"   # CMake leaves the last line without a newline
}
# shellcheck disable=SC2120
ms() { # ms [extra meson args]
  local bt
  case $BUILD_TYPE in RelWithDebInfo) bt=debugoptimized ;; Debug) bt=debug ;; MinSizeRel) bt=minsize ;; *) bt=release ;; esac
  if ! configured; then
    rm -rf "$B"
    meson setup "$B" "$S" --prefix="$PREFIX" --libdir=lib --buildtype="$bt" "$@"
    stamp
  fi
  ninja -C "$B" -j "$JOBS"
  ninja -C "$B" install
  grep -v '^#' "$B/meson-logs/install-log.txt" > "$FILES"
}

run_component() { # run_component <name> <release>: build in a subshell, output to the log
  local c=$1 log=$LOGS/$1.log rc
  set +e
  (
    set -Eeuo pipefail
    TAG=$2 FILES=$PREFIX/$REC/files/$c.txt B=$BLD/$c-$2 S='' url=''
    CSUM=$(cksum < "$REPO/components/$c.sh" | cut -d' ' -f1)
    # shellcheck disable=SC1090
    source "$REPO/components/$c.sh"
    [[ -n $url ]] && S=$(fetch "$c" "$TAG" "$url")
    if declare -F component_prepare >/dev/null; then (cd "$S" && component_prepare); fi
    if declare -F component_build >/dev/null; then component_build
    elif [[ -f $S/CMakeLists.txt ]]; then cm
    else ms
    fi
  ) > "$log" 2>&1
  rc=$?
  set -e
  if (( rc != 0 )); then
    say "!! $c FAILED (exit $rc). Last 40 lines of $log:"
    tail -n 40 "$log"
  fi
  return "$rc"
}

marker_present() { # is component <name> already in $PREFIX? (for adopting builds made without this tool)
  local pc l
  if [[ -n ${C_MARKER[$1]} ]]; then [[ -e $PREFIX/${C_MARKER[$1]} ]]; return; fi
  for pc in ${C_PC[$1]}; do
    [[ -e $PREFIX/lib/pkgconfig/$pc.pc || -e $PREFIX/share/pkgconfig/$pc.pc ]] && return 0
  done
  for l in ${C_LINKS[$1]}; do [[ -e $PREFIX/$l ]] && return 0; done
  return 1
}

write_installed() {
  local c
  {
    printf '# Components in this build and their releases, kept by hyprland-trixie.\n'
    for c in "${ORDER[@]}"; do [[ -n ${INST[$c]:-} ]] && printf '%s=%s\n' "$c" "${INST[$c]}"; done
  } > "$PREFIX/$REC/installed.part"
  mv "$PREFIX/$REC/installed.part" "$PREFIX/$REC/installed"
}

elf_files() { find "$PREFIX/bin" "$PREFIX/libexec" "$PREFIX/lib" -maxdepth 1 -type f 2>/dev/null; }

verify() { # every program and library resolves, and takes the libraries this build ships from this build
  local f out lib arrow path rest bad=0
  while IFS= read -r f; do
    # The compiler runtime copies themselves: loaded on their own they find Debian's libgcc_s, but inside a
    # program the program's RPATH covers them too
    case ${f##*/} in libstdc++.so.* | libgcc_s.so.*) continue ;; esac
    file -L "$f" | grep ELF >/dev/null || continue   # not grep -q: with pipefail, SIGPIPE turns hits into misses
    out=$(ldd "$f" 2>&1) || true
    if grep 'not found' <<<"$out" >/dev/null; then echo "UNRESOLVED in $f:"; grep 'not found' <<<"$out"; bad=1; fi
    while read -r lib arrow path rest; do
      if [[ $arrow == '=>' && -e $PREFIX/lib/$lib && $path != "$PREFIX/lib/"* ]]; then
        echo "$f takes $lib from $path instead of the build"; bad=1
      fi
    done <<<"$out"
  done < <(elf_files)
  app_verify
  (( bad == 0 ))
}

manifest() { # the Debian packages the host needs to run this build, worked out here where dpkg knows them
  local out=$PREFIX/$REC/runtime-packages.txt f l
  while IFS= read -r f; do file -L "$f" | grep ELF >/dev/null && ldd "$f"; done < <(elf_files) \
    | awk '$3 ~ /^\// {print $3}' | grep -v "^$PREFIX/" | sort -u \
    | while read -r l; do
        dpkg -S "$l" 2>/dev/null || dpkg -S "$(readlink -f "$l")" 2>/dev/null \
          || dpkg -S "/usr$l" 2>/dev/null || dpkg -S "${l#/usr}" 2>/dev/null || echo "UNOWNED: $l" >&2
      done | grep -v '^diversion by' | cut -d: -f1 | tr ',' '\n' | sed 's/^ *//' | sort -u > "$out"
  say "$(wc -l < "$out") runtime packages -> $out"
}

finish() {
  cp "$PINS" "$PREFIX/$REC/pins.env"
  say "== verify"
  verify || die "verification failed (above)"
  say "== runtime packages"
  manifest
}

# ---------- what to build ----------
want=()
read -ra want <<<"$APP_CORE"
want+=("$@")
for c in "${!INST[@]}"; do want+=("$c"); done   # keep everything this version already has
if [[ -n $ADOPT ]]; then
  for c in $(app_modules); do [[ -n ${PIN[$c]:-} ]] && marker_present "$c" && want+=("$c"); done
fi
order=$(build_order "${want[@]}") || exit 1
mapfile -t ORDER <<<"$order"

declare -A TAGS=()
for c in "${ORDER[@]}"; do
  if [[ ${C_RESOLVE[$c]} == none ]]; then
    # shellcheck disable=SC1090
    TAGS[$c]=$(source "$REPO/components/$c.sh" && component_tag)
  else
    TAGS[$c]=${PIN[$c]:-}
    [[ -n ${TAGS[$c]} ]] || die "$PINS has no line for $c (run: hyprland-trixie pin --add $VERSION $c)"
  fi
done

"$CXX" --version | head -n 1
say "Building $APP $VERSION into $PREFIX with $JOBS jobs ($BUILD_TYPE)"

if [[ -n $ADOPT ]]; then
  for c in "${ORDER[@]}"; do
    [[ ${TAGS[$c]} == system ]] && continue
    if marker_present "$c"; then INST[$c]=${TAGS[$c]}; say "== $c ${TAGS[$c]}: adopted"
    else warn "$c isn't in $PREFIX; the next build adds it"
    fi
  done
  write_installed
  finish
  say "Adopted $APP $VERSION."
  exit 0
fi

declare -A CHANGED=()
built=0
for c in "${ORDER[@]}"; do
  tag=${TAGS[$c]}
  if [[ $tag == system ]]; then say "== $c: Debian's own"; continue; fi
  stale=
  for n in ${C_NEEDS[$c]}; do [[ -n ${CHANGED[$n]:-} ]] && stale=$n; done
  if [[ ${INST[$c]:-} == "$tag" && -z $stale ]]; then say "== $c $tag: installed"; continue; fi
  # Replacing what was there: whatever uses it gets rebuilt too
  [[ -n ${INST[$c]:-} ]] && CHANGED[$c]=1
  say "== $c $tag${stale:+ (again, $stale changed)}   (log: $LOGS/$c.log)"
  run_component "$c" "$tag"
  INST[$c]=$tag
  write_installed
  built=$((built + 1))
done
finish
say "Done: $built built. $APP $VERSION is in $PREFIX"
