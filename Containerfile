# Containerfile - the disposable Debian 13 build environment, with GCC 16.
# Nothing in here reaches your system; `hyprland-trixie image` builds it, `podman rmi hyprland-trixie` removes it.
# The first two layers stay byte-for-byte the same so podman reuses them (GCC alone takes a long while).
FROM docker.io/library/debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get -y upgrade && apt-get install -y --no-install-recommends \
      ca-certificates build-essential git curl xz-utils file pkgconf python3 bison flex \
      cmake meson ninja-build \
      libgmp-dev libmpfr-dev libmpc-dev libisl-dev zlib1g-dev libzstd-dev \
      libwayland-dev libwayland-bin libdrm-dev libgbm-dev libegl-dev libgles-dev libglvnd-dev \
      libpixman-1-dev libcairo2-dev libpango1.0-dev libxcursor-dev uuid-dev libudev-dev libseat-dev \
      libdisplay-info-dev hwdata libeis-dev liblcms2-dev libre2-dev libmuparser-dev libglib2.0-dev \
      libreadline-dev libtomlplusplus-dev libzip-dev librsvg2-dev libjpeg-dev libwebp-dev libpng-dev \
      libmagic-dev libjxl-dev libheif-dev libpugixml-dev libffi-dev glslang-dev glslang-tools spirv-tools \
      libevdev-dev libmtdev-dev libxml2-dev xkb-data libsystemd-dev \
      libxcb1-dev libxcb-render0-dev libxcb-xfixes0-dev libxcb-icccm4-dev libxcb-composite0-dev \
      libxcb-res0-dev libxcb-errors-dev wayland-protocols libpipewire-0.3-dev libspa-0.2-dev libsdbus-c++-dev \
      qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev \
      qt6-wayland-dev qt6-wayland-private-dev qt6-shadertools-dev qt6-svg-dev \
      libcli11-dev libjemalloc-dev libpam0g-dev libpolkit-agent-1-dev libpolkit-gobject-1-dev libvulkan-dev \
 && rm -rf /var/lib/apt/lists/*

# GCC 16: Hyprland 0.56 needs C++26 (trixie ships GCC 14). Built against trixie's
# binutils 2.44 on purpose - prebuilt GCC 16 from other distros can emit asm 2.44 rejects.
ARG GCC_VER=16.2.0
RUN curl -fsSL "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz" | tar -xJ -C /tmp \
 && mkdir /tmp/gcc-build && cd /tmp/gcc-build \
 && /tmp/gcc-${GCC_VER}/configure --prefix=/opt/gcc-16 --enable-languages=c,c++ \
      --disable-multilib --disable-bootstrap --disable-nls --enable-checking=release --with-system-zlib \
 && make -j"$(nproc)" && make install-strip \
 && cd / && rm -rf /tmp/gcc-* \
 && /opt/gcc-16/bin/g++ --version | head -1

# Everything added since goes in packages.txt, so adding a package never rebuilds GCC.
# `hyprland-trixie pin` and `build` append what a new version turns out to need.
COPY packages.txt /tmp/packages.txt
RUN apt-get update && sed 's/#.*//' /tmp/packages.txt | xargs apt-get install -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* /tmp/packages.txt
