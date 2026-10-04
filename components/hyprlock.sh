# shellcheck shell=bash disable=SC2034
desc="Screen locker"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprlock.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprlang hyprgraphics hyprwayland-scanner wayland-protocols xkbcommon"
links="bin/hyprlock"
