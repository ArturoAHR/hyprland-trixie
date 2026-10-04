# shellcheck shell=bash disable=SC2034
desc="Answers admin password prompts (polkit agent)"
app=hyprland
kind=module
url=https://github.com/hyprwm/hyprpolkitagent.git
resolve=compatible      # the newest release whose requirements these pins meet
needs="hyprutils hyprtoolkit hyprgraphics hyprlang"
links="lib/systemd/user/hyprpolkitagent.service"
