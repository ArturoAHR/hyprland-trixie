# shellcheck shell=bash disable=SC2034
desc="Wayland protocol definitions (build-time data)"
kind=lib
url=https://gitlab.freedesktop.org/wayland/wayland-protocols.git
tags='^[0-9]+\.[0-9]+$'
resolve=system-or-newest
pc=wayland-protocols

component_prepare() {
  # Debian 13's wayland-scanner 1.23 doesn't know the 'frozen' attribute newer XMLs use; --strict makes that fatal
  [[ ! -f include/wayland-protocols/meson.build ]] || sed -i "/'--strict',/d" include/wayland-protocols/meson.build
}
component_build() { ms -Dtests=false; }
