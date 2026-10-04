# shellcheck shell=bash disable=SC2034
desc="Keyboard keymap library"
kind=lib
url=https://github.com/xkbcommon/libxkbcommon.git
tags='^xkbcommon-[0-9]+\.[0-9]+\.[0-9]+$'
resolve=system-or-newest
pc="xkbcommon xkbregistry"

# Data paths point at the system, so your keyboard layouts (including custom ones) keep working
component_build() {
  ms -Denable-docs=false -Denable-tools=false -Denable-x11=false -Denable-wayland=false \
     -Denable-bash-completion=false \
     -Dxkb-config-root=/usr/share/X11/xkb -Dxkb-config-extra-path=/etc/xkb -Dx-locale-root=/usr/share/X11/locale
}
