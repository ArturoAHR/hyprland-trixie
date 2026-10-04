# shellcheck shell=bash disable=SC2034  # APP_* are read by the scripts that load the app
# The Hyprland compositor, the libraries Debian 13 lacks or ships too old, and optional modules.

APP_ROOT=hyprland                    # the component whose release names the version
APP_CORE="gcc-runtime hyprland xdph" # always built, with everything they need
APP_NEWEST=""                        # components pinned to their newest release, whatever they declare
# Hyprland 0.56 is C++26: GCC 16, built in the image (Debian 13 ships GCC 14)
APP_CC=/opt/gcc-16/bin/gcc
APP_CXX=/opt/gcc-16/bin/g++

app_verify() { # in the container, after a build
  local rt; rt=$(mktemp -d)   # Hyprland refuses to start without XDG_RUNTIME_DIR, and containers don't set it
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$rt}" "$PREFIX/bin/Hyprland" --version | head -n 3
}

LAUNCHER_SCRIPT="$BIN_DIR/hyprland-session"

app_on_use() { # on the host, after `current` moved; $CUR is $OPT_ROOT/hyprland/current
  cat > "$LAUNCHER_SCRIPT" <<EOF
#!/bin/sh
# hyprland-session - written by hyprland-trixie; \`hyprland-trixie use <version>\` rewrites it.
# Starts the Hyprland version $CUR points at, then clears what it exported to systemd.
H="$CUR"
export PATH="$BIN_DIR:\$PATH"
${AQ_DRM_DEVICES:+export AQ_DRM_DEVICES="$AQ_DRM_DEVICES"}
"\$H/bin/start-hyprland" --path "\$H/bin/Hyprland" "\$@"
rc=\$?
systemctl --user unset-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE \\
  XDG_CURRENT_DESKTOP QT_QPA_PLATFORMTHEME 2>/dev/null
exit \$rc
EOF
  chmod +x "$LAUNCHER_SCRIPT"
  starter_config
}

app_on_unlink() {
  if [[ -f $LAUNCHER_SCRIPT ]] && grep -q 'written by hyprland-trixie' "$LAUNCHER_SCRIPT"; then
    rm -v "$LAUNCHER_SCRIPT"
  fi
  return 0
}

starter_config() {
  local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua" menu=$LAUNCHER agent=$POLKIT_AGENT
  if [[ -e $cfg ]]; then
    say "Kept your $cfg"
  else
    mkdir -p "$(dirname "$cfg")"
    cp "$CUR/share/hypr/hyprland.lua" "$cfg"
    [[ -n $TERMINAL ]] && sed -i "s|^local terminal\( *\)= \".*\"|local terminal\1= \"$TERMINAL\"|" "$cfg"
    if [[ -z $menu ]]; then
      if [[ -n ${INST[hyprlauncher]:-} ]]; then menu=hyprlauncher
      elif [[ -n ${INST[hyprland-guiutils]:-} ]]; then menu=hyprland-run
      fi
    fi
    [[ -n $menu ]] && sed -i "s|^local menu\( *\)= \".*\"|local menu\1= \"$menu\"|" "$cfg"
    [[ -z $agent && -n ${INST[hyprpolkitagent]:-} ]] && agent="systemctl --user start hyprpolkitagent"
    if [[ -n $QT_PLATFORM_THEME || -n $agent ]]; then
      {
        printf '\n-- added by hyprland-trixie\n'
        [[ -n $QT_PLATFORM_THEME ]] && printf 'hl.env("QT_QPA_PLATFORMTHEME", "%s")\n' "$QT_PLATFORM_THEME"
        [[ -n $agent ]] && printf 'hl.on("hyprland.start", function ()\n    hl.exec_cmd("%s")\nend)\n' "$agent"
      } >> "$cfg"
    fi
    say "Wrote $cfg (terminal: ${TERMINAL:-default}, launcher: ${menu:-default})"
  fi
  local rt; rt=$(mktemp -d)
  XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$rt}" "$CUR/bin/Hyprland" --verify-config -c "$cfg" | tail -n 1 \
    || warn "Hyprland reports a problem in $cfg (above)"
}
