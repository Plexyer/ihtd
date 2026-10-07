#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
cargo test --workspace --locked
cd app
flutter pub get
flutter analyze lib integration_test/app_test.dart
flutter build linux --release
printf '%s\n' 'Ready: app/build/linux/x64/release/bundle/ihtd'
