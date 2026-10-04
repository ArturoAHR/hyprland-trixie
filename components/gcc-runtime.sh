# shellcheck shell=bash disable=SC2034
desc="GCC 16's C++ runtime, shipped inside the build because Debian 13's libstdc++ is GCC 14's"
kind=lib
resolve=none            # follows the compiler in the image, not a release
marker=lib/libstdc++.so.6

component_tag() { printf 'gcc-%s\n' "$("$CXX" -dumpfullversion)"; }
component_build() {
  local l p
  for l in libstdc++.so.6 libgcc_s.so.1; do
    p=$("$CXX" -print-file-name="$l")
    [[ $p == /* ]] || { echo "cannot locate $l via $CXX"; return 1; }
    cp -fL "$p" "$PREFIX/lib/$l"
    printf '%s\n' "$PREFIX/lib/$l"
  done > "$FILES"
}
