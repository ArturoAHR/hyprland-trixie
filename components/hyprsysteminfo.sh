# shellcheck shell=bash disable=SC2034
desc="System information window"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprsysteminfo.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprtoolkit hyprutils"
links="bin/hyprsysteminfo"

# Two workarounds for 0.2.0 on Debian 13:
# - it includes pciutils' pci.h from C++, and Debian's pci.h (pciutils 3.13) has no extern "C" guard;
# - it downloads glaze when it isn't installed (Debian doesn't package it) but never adds it to its include path.
component_prepare() {
  grep -q '^extern "C" {$' src/utils/SystemInfo.cpp ||
    sed -i 's|^#include <pci/pci.h>$|extern "C" {\n#include <pci/pci.h>\n}|' src/utils/SystemInfo.cpp
}
component_build() { cm "-DCMAKE_CXX_FLAGS=-isystem $B/_deps/glaze-src/include"; }
