# shellcheck shell=bash disable=SC2034
desc="Generates C++ Wayland bindings at build time"
kind=lib
url=https://github.com/hyprwm/hyprwayland-scanner.git
resolve=flake           # the release that contains the commit Hyprland's flake.lock tests
pc=hyprwayland-scanner
