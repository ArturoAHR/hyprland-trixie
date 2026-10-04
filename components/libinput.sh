# shellcheck shell=bash disable=SC2034
desc="Input device library"
kind=lib
url=https://gitlab.freedesktop.org/libinput/libinput.git
tags='^[0-9]+\.[0-9]+\.[0-8]?[0-9]$'   # x.y.9xx tags are release candidates
resolve=system-or-newest
pc=libinput

# Its udev rules stay in the build folder; Debian's own libinput keeps handling the system's devices
component_build() {
  ms -Dlua-plugins=disabled -Dlibwacom=false -Ddebug-gui=false -Dtests=false -Ddocumentation=false \
     -Dudev-dir="$PREFIX/lib/udev" -Dzshcompletiondir=no
}
