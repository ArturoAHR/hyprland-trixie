# shellcheck shell=bash disable=SC2034
desc="xdg-desktop-portal-hyprland: screen sharing and screenshots for apps"
app=hyprland
kind=core
url=https://github.com/hyprwm/xdg-desktop-portal-hyprland.git
resolve=flake
flake=xdph
needs="hyprutils hyprlang hyprwayland-scanner hyprland-protocols wayland-protocols"
links="bin/hyprland-share-picker
       share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service
       share/xdg-desktop-portal/portals/hyprland.portal
       share/xdg-desktop-portal/hyprland-portals.conf
       lib/systemd/user/xdg-desktop-portal-hyprland.service"
marker=libexec/xdg-desktop-portal-hyprland

# The portal runs hyprland-share-picker by searching PATH, and the systemd user manager that starts the
# portal doesn't always have $BIN_DIR on its PATH.
DROPIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/xdg-desktop-portal-hyprland.service.d"
component_on_use() {
  mkdir -p "$DROPIN_DIR"
  printf '%s\n' "# Written by hyprland-trixie, so the portal finds hyprland-share-picker." \
    "[Service]" "Environment=PATH=$BIN_DIR:/usr/local/bin:/usr/bin:/bin" > "$DROPIN_DIR/hyprland-trixie.conf"
}
component_on_unlink() {
  rm -fv "$DROPIN_DIR/hyprland-trixie.conf"
  rmdir "$DROPIN_DIR" 2>/dev/null || true
}
