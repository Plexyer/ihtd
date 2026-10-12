#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/flutter/bin:/root/.cargo/bin:$PATH"
cd /workspace
cargo test --workspace --locked
cd app
flutter pub get --enforce-lockfile
flutter analyze lib test integration_test
flutter test test/android_documents_test.dart
GDK_BACKEND=x11 dbus-run-session -- xvfb-run -a -s '-screen 0 1600x1000x24' flutter test integration_test/app_test.dart -d linux
GDK_BACKEND=x11 dbus-run-session -- xvfb-run -a -s '-screen 0 1600x1000x24' flutter test integration_test/phone_layout_test.dart -d linux
flutter build linux --release
cd /workspace
bash packaging/fedora/package.sh
