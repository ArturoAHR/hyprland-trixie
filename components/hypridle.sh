# shellcheck shell=bash disable=SC2034
desc="Idle daemon: locks, dims or suspends after inactivity"
app=hyprland
kind=module
url=https://github.com/hyprwm/hypridle.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprlang hyprland-protocols hyprwayland-scanner wayland-protocols"
links="bin/hypridle lib/systemd/user/hypridle.service"
