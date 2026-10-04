# shellcheck shell=bash disable=SC2034
desc="Color picker"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprpicker.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprwayland-scanner wayland-protocols xkbcommon"
links="bin/hyprpicker"
