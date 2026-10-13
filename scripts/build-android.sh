#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
cargo test --workspace --locked
cd app
flutter pub get --enforce-lockfile
flutter analyze lib integration_test/app_test.dart
# Builds a test/candidate APK. Production signing is a separate protected step.
flutter build apk --release --target-platform android-arm64
printf '%s\n' 'Development-signed test APK: app/build/app/outputs/flutter-apk/app-release.apk'
