# shellcheck shell=bash disable=SC2034
desc="Lua for Hyprland's Lua config, linked in statically (Debian 13 ships 5.4)"
kind=lib
resolve=lua             # the series Hyprland asks for, newest release, checksum from lua.org
marker=lua/lib/liblua.a

# Into $PREFIX/lua, so its lua and luac never land on PATH
component_build() {
  local t=$SRC/lua-$TAG.tar.gz series=${TAG%.*}
  if [[ ! -f $t ]]; then curl -fL -o "$t.part" "https://www.lua.org/ftp/lua-$TAG.tar.gz" && mv "$t.part" "$t"; fi
  echo "${PIN[lua.sha256]}  $t" | sha256sum -c -
  rm -rf "$B"; mkdir -p "$B"
  tar -xzf "$t" -C "$B" --strip-components=1
  make -C "$B" linux MYCFLAGS=-fPIC
  make -C "$B" install INSTALL_TOP="$PREFIX/lua"
  cat > "$PREFIX/lib/pkgconfig/lua$series.pc" <<PC
prefix=$PREFIX/lua
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Lua
Description: Lua $series (static, private to Hyprland)
Version: $TAG
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
PC
  pkg-config --modversion "lua$series"
  { find "$PREFIX/lua" -type f; printf '%s\n' "$PREFIX/lib/pkgconfig/lua$series.pc"; } > "$FILES"
}
