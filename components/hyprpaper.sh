# shellcheck shell=bash disable=SC2034
desc="Wallpaper daemon"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprpaper.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprlang hyprtoolkit hyprwire hyprwayland-scanner"
links="bin/hyprpaper lib/systemd/user/hyprpaper.service"
