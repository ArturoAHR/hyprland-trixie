# shellcheck shell=bash disable=SC2034
desc="IPC protocol library and scanner"
kind=lib
url=https://github.com/hyprwm/hyprwire.git
resolve=flake           # the release that contains the commit Hyprland's flake.lock tests
needs="hyprutils"
pc="hyprwire hyprwire-scanner"
