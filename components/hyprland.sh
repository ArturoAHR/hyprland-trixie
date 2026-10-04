# shellcheck shell=bash disable=SC2034
desc="The Hyprland compositor, hyprctl and start-hyprland"
app=hyprland
kind=core
url=https://github.com/hyprwm/Hyprland.git
resolve=self            # its release is the version
needs="lua wayland-protocols xkbcommon libinput hyprutils hyprlang hyprwayland-scanner hyprwire
       hyprland-protocols aquamarine hyprgraphics hyprcursor"
pc=hyprland
links="bin/Hyprland bin/hyprctl bin/start-hyprland"
check_skip="hyprpm hyprtester tests example"

# hyprpm installs plugins by compiling them against Hyprland's headers on your machine, which needs this
# image's GCC 16; leave it out.
component_build() { cm -DNO_HYPRPM=ON; }
