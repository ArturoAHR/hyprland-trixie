# hyprland-trixie

Build [Hyprland](https://hypr.land) and the tools around it for Debian 13 (trixie), next to the desktop you already have.

Debian 13 doesn't package Hyprland, and current Hyprland needs more than Debian 13 can give it: a C++26 compiler (GCC 16, where Debian ships 14), Lua 5.5, and newer wayland-protocols, xkbcommon and libinput than Debian carries. `hyprland-trixie` compiles all of that in a disposable podman container and installs each Hyprland version into its own folder in your home. Each folder finds its libraries on its own, so versions sit side by side, and switching or rolling back is one command. Your display manager, your current desktop and your system libraries stay as they are.

## What goes where

| Path | What |
|---|---|
| `~/.local/opt/hyprland/<version>/` | One complete build: Hyprland, its libraries, the portal, the modules you chose |
| `~/.local/opt/hyprland/current` | Relative link to the version your next session starts |
| `~/.local/bin/Hyprland`, `hyprctl`, `start-hyprland`, … | Links through `current`; the same for each module's programs |
| `~/.local/bin/hyprland-session` | Starts the current version from a text console |
| `~/.local/share/dbus-1/services/`, `~/.local/share/xdg-desktop-portal/`, `~/.config/systemd/user/` | The portal's files and the modules' user services, linked through `current` |
| `~/.local/opt/quickshell/<version>/`, `…/current`, `~/.local/bin/quickshell` | The same for Quickshell, if you build it |
| `~/.cache/hyprland-trixie/` | Sources, build folders per version, logs |

The only change outside your home folder is the handful of runtime libraries `deps --install` adds with apt, and only when you run it. Nothing gets upgraded on the way.

## Requirements

- Debian 13 on x86_64.
- Rootless podman: `sudo apt install podman`.
- Disk space: about 2 GB for the build image, about 3 GB of build cache per Hyprland version (`prune` frees it) and about 100 MB per installed version.
- Time: the first `image` compiles GCC 16 from source, which takes a while; every later build reuses it. A full Hyprland build then takes around ten minutes on a recent laptop, half of it Hyprland itself, and adding a module to a built version takes a minute or two.
- RAM: builds run one compile job per CPU, capped at one per 2 GB of free memory.
- NVIDIA: the driver's kernel modesetting must be on. `sudo cat /sys/module/nvidia_drm/parameters/modeset` should print `Y`. Recent drivers turn it on by default. If yours prints `N`, add `nvidia-drm.modeset=1` to the kernel command line.

## Quick start

```bash
git clone https://github.com/ArturoAHR/hyprland-trixie.git
cd hyprland-trixie
./hyprland-trixie image                  # the build container; compiles GCC 16 the first time
./hyprland-trixie build 0.56.2           # Hyprland 0.56.2 plus the modules in your config
./hyprland-trixie deps 0.56.2 --install  # the runtime libraries it needs from Debian (sudo apt)
./hyprland-trixie use 0.56.2             # make it current and link its programs
```

Then switch to a text console (Ctrl+Alt+F3), log in and run `hyprland-session`. Logging out of Hyprland brings you back to that console.

To run the tool from anywhere, link it: `ln -s "$PWD/hyprland-trixie" ~/.local/bin/`.

`use` writes a starter `~/.config/hypr/hyprland.lua` from Hyprland's default if you don't have one, and never touches one you do have. To start Hyprland from your display manager's session menu, see [Display manager entry](#display-manager-entry).

## Commands

```
hyprland-trixie [quickshell] <command>

image                         build or update the build container
pin <version|latest>          work out the release of every component: writes pins/<app>/<version>.env
pin <version> --add <name...> pin components that version's file lacks
build <version> [module...]   build <version> with the modules in your config plus any named here
deps <version> [--install]    check the Debian packages <version> needs at runtime; --install adds missing ones
use <version>                 make <version> the one your next session starts, and link its programs
list                          installed versions, the current one, their modules and cache sizes
modules                       optional modules you can build in
remove <version> [module...]  delete a version, or only some modules from it
prune [<version>]             delete build caches: of <version>, or of every version not installed
adopt <version>               take over a build made by the earlier runbook scripts without rebuilding it
unlink                        undo `use`: remove the links and the current pointer, keep the versions
config                        create ~/.config/hyprland-trixie/config.env to change preferences
```

## Preferences

`hyprland-trixie config` writes `~/.config/hyprland-trixie/config.env` with every setting commented out. Uncomment what you want to change. The environment overrides it for one command: `MODULES="hyprlock hypridle" ./hyprland-trixie build 0.56.2`.

| Setting | Default | What |
|---|---|---|
| `MODULES` | `hyprland-guiutils` | Optional modules built into every Hyprland version |
| `JOBS` | automatic | Parallel compile jobs |
| `BUILD_TYPE` | `Release` | `RelWithDebInfo` gives readable crash backtraces at the cost of size |
| `AQ_DRM_DEVICES` | empty | GPU order on multi-GPU machines (see [Several GPUs](#several-gpus)) |
| `TERMINAL` | `kitty` | Terminal in the starter config |
| `LAUNCHER` | automatic | Launcher in the starter config: `hyprlauncher` if built, else `hyprland-run` |
| `QT_PLATFORM_THEME` | empty | `QT_QPA_PLATFORMTHEME` for Qt apps, e.g. `kde` or `qt6ct` |
| `POLKIT_AGENT` | automatic | Command that answers admin password prompts; `hyprpolkitagent` if built. On KDE: `/usr/lib/x86_64-linux-gnu/libexec/polkit-kde-authentication-agent-1` |
| `OPT_ROOT`, `BIN_DIR`, `CACHE_DIR` | `~/.local/opt`, `~/.local/bin`, `~/.cache/hyprland-trixie` | Where things go |

The starter-config settings only apply when `use` writes a new config. Do note that a build records its own folder inside its libraries, so a build can't be moved. If you change `OPT_ROOT`, rebuild.

## Modules

| Module | What |
|---|---|
| `hyprland-guiutils` | The dialogs Hyprland opens itself (an app not responding, permission prompts) and `hyprland-run`. Hyprland warns at startup without it |
| `hyprlock` | Screen locker |
| `hypridle` | Idle daemon: locks, dims or suspends after inactivity |
| `hyprpaper` | Wallpaper daemon |
| `hyprsunset` | Blue-light filter |
| `hyprpicker` | Color picker |
| `hyprpolkitagent` | Answers admin password prompts |
| `hyprlauncher` | App launcher with search |
| `hyprsysteminfo` | System information window |
| `hyprshutdown` | Logout and shutdown screen |

Add one to every future build through `MODULES`, or to one version right away:

```bash
./hyprland-trixie build 0.56.2 hyprlock hypridle
```

That compiles only the new modules. Everything already in the version is skipped, even after its build cache was pruned, because each version records what it contains in `share/hyprland-trixie/installed`. If the version is current, its new programs get linked straight away. `remove 0.56.2 hyprlock` takes a module out again.

The daemons ship systemd user services, linked into `~/.config/systemd/user`. A Hyprland session started from a console doesn't activate `graphical-session.target`, so start them from your config:

```lua
hl.on("hyprland.start", function ()
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprpaper")
end)
```

hyprlock checks passwords through PAM. Without its own `/etc/pam.d/hyprlock`, PAM falls back to Debian's `other` rules, which accept your normal login password. To use the rules hyprlock ships instead, copy them in: `sudo cp ~/.local/opt/hyprland/current/etc/pam.d/hyprlock /etc/pam.d/`.

## Updating Hyprland

```bash
./hyprland-trixie pin latest             # writes pins/hyprland/<new>.env and prints what it chose
./hyprland-trixie build <new>
./hyprland-trixie deps <new> --install
./hyprland-trixie use <new>              # your next session starts <new>
./hyprland-trixie use <old>              # changed your mind: back to the old one
```

The old version stays installed until you `remove` it, and its build cache until you `prune` it.

`pin` picks a release of every component for the new version and writes the reason next to each line:

- **The hypr libraries and the portal** come from Hyprland's own `flake.lock`, which pins the exact commits upstream builds and tests together. `pin` takes the first release that contains each pinned commit, then the newest bug-fix release in that series.
- **wayland-protocols, xkbcommon and libinput** use Debian's copy when it meets Hyprland's minimum, and otherwise the newest release.
- **Lua** is the newest release of the series Hyprland asks for, with the checksum lua.org publishes.
- **Modules** get the newest release whose declared minimums the other pins meet.
- Afterwards it checks every pin against every component's declared minimums and raises any that fall short.

Before a build, the tool reads every component's build files for the libraries they require and checks the image has them. When something is missing, it asks Debian which package provides it, adds that to `packages.txt` and rebuilds the image's last layer. GCC stays cached.

What it can't foresee is a component that fails to compile, which still happens: Debian's wayland-scanner, for one, rejected newer protocol files until `components/wayland-protocols.sh` learned to work around it. When a component fails, the build stops, prints the end of its log and keeps the full one in `~/.cache/hyprland-trixie/logs/hyprland/<version>/<component>.log`. Fix it in `components/<component>.sh` or by editing the pins file, then run `build` again. It resumes where it stopped.

## Switching versions

```bash
./hyprland-trixie list
./hyprland-trixie use 0.56.2
```

`use` moves `current`, relinks the programs of the modules that version has, removes links to modules it lacks, and rewrites `hyprland-session`. Your next session starts that version. A running session keeps the version it started with.

## Caches

Each Hyprland version keeps its own build folders in `~/.cache/hyprland-trixie/build/hyprland/<version>/`. Sources are shared by every version that uses the same release. Hyprland's own build folder is about 2.5 GB, so caches add up.

- `prune <version>` deletes one version's build folders. The version keeps working, and adding a module to it still compiles only that module. Only rebuilding a component from scratch takes longer.
- `prune` deletes the build folders of versions you removed, and the sources no installed version uses.

## Quickshell

[Quickshell](https://quickshell.org) is a toolkit for writing your own bar, launcher and widgets in QtQuick. It installs like Hyprland, under `~/.local/opt/quickshell/<version>`:

```bash
./hyprland-trixie quickshell pin latest
./hyprland-trixie quickshell build <version>
./hyprland-trixie quickshell deps <version> --install
./hyprland-trixie quickshell use <version>
```

It builds with Debian's own GCC 14 against Debian's Qt, and it doesn't depend on any Hyprland version. Start your shell from the Hyprland config with `hl.exec_cmd("quickshell")`. Quickshell's developers suggest `BUILD_TYPE=RelWithDebInfo` so crash reports are readable; bear in mind it makes the binary about 200 MB instead of 12.

## Display manager entry

Display managers read sessions from system folders only, so this one step needs sudo. SDDM and GDM both read `/usr/local/share/wayland-sessions`, which apt never touches:

```bash
sudo mkdir -p /usr/local/share/wayland-sessions
sudo tee /usr/local/share/wayland-sessions/hyprland-trixie.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland (hyprland-trixie)
Exec=$HOME/.local/bin/hyprland-session
Type=Application
DesktopNames=Hyprland
EOF
```

The entry starts whichever version is current.

## Several GPUs

Hyprland renders on the GPU that drives your screens and usually picks it on its own. If it picks wrong, which shows as a black screen or slow rendering, set `AQ_DRM_DEVICES` in your config to the GPUs in order, the one your screens hang off first, and run `use` again to rewrite `hyprland-session`. `ls -l /dev/dri/by-path/` next to `lspci | grep -Ei 'vga|3d|display'` tells you which card is which.

## Removing

```bash
./hyprland-trixie unlink
./hyprland-trixie quickshell unlink
rm -rf ~/.local/opt/hyprland ~/.local/opt/quickshell ~/.cache/hyprland-trixie
podman rmi hyprland-trixie
```

`deps --install` installs only the runtime packages your system doesn't have yet. On the Debian 13 system with KDE Plasma 6 this was tested on, that came to seven small libraries for Hyprland 0.56.2 with `hyprland-guiutils`, and nothing more for Quickshell or the other modules:

```
libmuparser2v5 libpugixml1v5 libsdbus-c++2 libseat1 libtomlplusplus3t64 libxcb-errors0 libiniparser4
```

apt marks them as installed by hand, so `autoremove` leaves them alone. If nothing else of yours uses them, remove them with `sudo apt remove` and that list; apt shows anything else that would go with them before it asks. On another system the set differs: each version's `share/hyprland-trixie/runtime-packages.txt` lists every package it needs, whether it was already installed or not.

## How it works

- **Container.** `Containerfile` is Debian 13 with the development packages and GCC 16 built from source against Debian's binutils 2.44. Prebuilt GCC 16 from other distributions can emit assembly that binutils 2.44 rejects. Builds run as you (`--userns=keep-id`), with only `~/.local/opt` and the cache folder mounted.
- **One folder per version.** Everything installs into `~/.local/opt/hyprland/<version>`, linked with an `RPATH` to its own `lib/`. That's `DT_RPATH`, not `RUNPATH`, so it also covers the libraries' own dependencies. GCC 16's `libstdc++` ships inside, because Debian 13's is older than the code needs. The folder path is also baked into pkg-config files and the portal's service files, which is why a build can't move.
- **Two copies of libinput and xkbcommon.** The image holds Debian's older libinput and xkbcommon too, because Qt's development packages pull them in, and CMake can link those instead of the newer copies it compiled against. Every CMake build is pointed at the copies in the build folder.
- **The share picker.** The portal runs `hyprland-share-picker` by searching `PATH`. The systemd user manager that starts the portal doesn't always have `~/.local/bin` on its `PATH`, so `use` adds a drop-in that gives it one.
- **hyprpm** is left out. It installs plugins by compiling them on your machine against Hyprland's headers, which needs GCC 16 outside the container.

### Layout

```
hyprland-trixie        the command (runs on your machine)
lib/build.sh           builds a version, inside the container
lib/resolve.sh         works out pins and checks the image, inside the container
lib/common.sh          shared by both
apps/<app>.sh          hyprland and quickshell: what's always built, which compiler, session setup
components/<name>.sh   one per component: where it comes from, what it needs, how it builds, what gets linked
pins/<app>/<version>.env   the release of every component, per version
config.defaults.env    preferences and their defaults
packages.txt           Debian packages added to the image after GCC
```

A component file is a few variables and, when the defaults don't fit, a function or two:

```bash
desc="Screen locker"
app=hyprland
kind=module                      # core (always built), lib (built when needed) or module (optional)
url=https://github.com/hyprwm/hyprlock.git
resolve=compatible               # self, flake, system-or-newest, lua, newest or compatible
needs="hyprutils hyprlang hyprgraphics hyprwayland-scanner wayland-protocols xkbcommon"
links="bin/hyprlock"             # linked into BIN_DIR (bin/), XDG data (share/), systemd user units
component_build() { cm -DSOME_OPTION=ON; }   # optional; the default runs CMake or Meson as found
```

`cm` and `ms` configure, build and install with CMake or Meson. Add a component file, then `pin <version> --add <name>` for the versions that should have it.

## Tested on

Debian 13 with an NVIDIA GPU, next to KDE Plasma 6.

## License

MIT
