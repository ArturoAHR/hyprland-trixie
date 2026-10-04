# shellcheck shell=bash disable=SC2034
desc="Blue-light filter"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprsunset.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprlang hyprland-protocols hyprwayland-scanner wayland-protocols"
links="bin/hyprsunset lib/systemd/user/hyprsunset.service"
