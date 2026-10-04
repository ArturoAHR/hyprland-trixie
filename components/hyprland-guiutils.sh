# shellcheck shell=bash disable=SC2034
desc="Dialogs Hyprland opens itself (app not responding, permission prompts) and hyprland-run"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprland-guiutils.git
resolve=flake
needs="hyprtoolkit hyprutils hyprlang xkbcommon"
links="bin/hyprland-dialog bin/hyprland-run bin/hyprland-welcome bin/hyprland-update-screen
       bin/hyprland-donate-screen"
