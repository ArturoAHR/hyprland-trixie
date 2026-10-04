# shellcheck shell=bash disable=SC2034  # APP_* are read by the scripts that load the app
# Quickshell, the QtQuick toolkit for building your own bar, launcher and widgets.

APP_ROOT=quickshell
APP_CORE="quickshell"
# Quickshell declares wayland-protocols >= 1.41 but uses protocols newer than Debian's 1.44
# (ext-background-effect), so it gets the newest release, as build-time data in its own folder.
APP_NEWEST="wayland-protocols"
# Debian's own GCC 14, the compiler Debian's Qt 6.8 was built with
APP_CC=/usr/bin/gcc
APP_CXX=/usr/bin/g++

app_verify() { "$PREFIX/bin/quickshell" --version || true; }
app_on_use() { return 0; }
app_on_unlink() { return 0; }
