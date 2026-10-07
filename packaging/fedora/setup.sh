#!/usr/bin/env bash
# Run only inside the dedicated Fedora build environment, as root.
set -euo pipefail
dnf install -y --allowerasing git curl unzip xz tar clang cmake ninja-build pkgconf-pkg-config gtk3-devel gcc-c++ rpm-build xorg-x11-server-Xvfb xorg-x11-xauth mesa-dri-drivers mesa-libEGL mesa-libGL dbus-daemon procps-ng dejavu-sans-fonts
if [[ ! -x /opt/flutter/bin/flutter ]]; then
  curl -fL --retry 3 -o /tmp/ihtd-flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
  echo '2132e990f236f8d22e7c6314b29a191a95b10d7cbcfec9b4e2e303d996652cbb  /tmp/ihtd-flutter.tar.xz' | sha256sum -c -
  tar xf /tmp/ihtd-flutter.tar.xz -C /opt
fi
if [[ ! -x /root/.cargo/bin/rustup ]]; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/ihtd-rustup.sh
  sh /tmp/ihtd-rustup.sh -y --profile minimal --default-toolchain 1.93.1
fi
export PATH="/opt/flutter/bin:/root/.cargo/bin:$PATH"
git config --global --add safe.directory /opt/flutter
flutter --disable-analytics
flutter precache --linux
