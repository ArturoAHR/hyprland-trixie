# shellcheck shell=bash disable=SC2034
desc="Graceful logout and shutdown screen"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprshutdown.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprtoolkit hyprutils"
links="bin/hyprshutdown"
