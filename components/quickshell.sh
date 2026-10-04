# shellcheck shell=bash disable=SC2034
desc="Quickshell, the QtQuick toolkit for your own bar, launcher and widgets"
app=quickshell
kind=core
url=https://github.com/quickshell-mirror/quickshell.git
resolve=self
needs="wayland-protocols"
links="bin/quickshell bin/qs"

component_build() { cm -DDISTRIBUTOR="hyprland-trixie" -DCRASH_HANDLER=OFF; }
