# Build and test IHTD

The tested Windows build uses Flutter 3.47.5 (Dart 3.13.4), Rust 1.93.1 for
the bridge, and flutter_rust_bridge 2.13.0. The root Rust tests also passed with
Rust 1.91.1. Use the checked-in Pub and Cargo lockfiles. Generated bridge files
are included, so building does not require the code generator.

## Windows 11 x64

Install Flutter, Rust through rustup, and Visual Studio's **Desktop development
with C++** workload, including a Windows SDK. Put flutter and cargo on PATH.
From the repository root run:

```powershell
./scripts/build-windows.ps1
```

The result is `app/build/windows/x64/runner/Release/ihtd.exe`. Distribute the
whole Release directory, including its data directory and DLLs. On a machine
without the C++ runtime, install Microsoft's x64 Visual C++ Redistributable.
See [Flutter's Windows packaging guidance](https://docs.flutter.dev/platform-integration/windows/building).

## Fedora x64

Fedora 44 x86-64 RPM and portable packages are available in `dist/fedora`.
See [installation](../packaging/fedora/INSTALL.md) and
[packaging/rebuild instructions](../packaging/fedora/README.md).
The Linux build, integration tests, and installed-release launch passed in
Fedora under WSL; physical laptop verification is still pending.

This target must be built on Linux.
Install Flutter 3.47.5's Linux SDK and Rust via rustup, then install the native
build dependencies (Fedora package names corresponding to Flutter's Linux
requirements):

```sh
sudo dnf install git curl unzip xz clang cmake ninja-build pkgconf-pkg-config gtk3-devel gcc-c++
```

Ensure Flutter's bin directory and `$HOME/.cargo/bin` are on PATH. From the
repository root:

```sh
bash scripts/build-linux.sh
./app/build/linux/x64/release/bundle/ihtd
```

Keep the entire bundle directory together when moving the app. The Fedora
desktop must have GTK3 and the usual C++ runtime installed. Flutter documents
the [Linux build prerequisites](https://docs.flutter.dev/platform-integration/linux/setup)
and [distribution dependencies](https://docs.flutter.dev/platform-integration/linux/building).

The Rust bridge's native-assets hook compiles Rust and bundled SQLite during
the Flutter build. Flutter regenerates platform plugin registration at build
time. No SQLite server or separate database installation is required.

## Tests and development

```sh
cargo test --workspace --locked
cargo fmt --all --check
cd app
flutter pub get
flutter analyze lib integration_test/app_test.dart
flutter test integration_test/app_test.dart -d windows
```

Use `-d linux` for the integration test on a Linux graphical desktop.
`flutter run -d windows` or `flutter run -d linux` starts a development session.
Tests use temporary collections, not user documents. The integration test
covers UI creation, flushing title edits, dragging into a container, moving a
shared placement to the top level, reordering, shared completion, tag defaults,
and reopening a saved document. Rust tests cover domain rules and migration
from the original .ihtd format.

If you change the public Rust bridge API, install codegen version 2.13.0 and
run `flutter_rust_bridge_codegen generate` inside app. Its version must match
the Rust and Dart bridge packages.

## Android follow-up

The Android runner is scaffolded and the shared Rust core is platform-neutral.
Android still needs Storage Access Framework document-provider handling,
phone-specific interaction work, and device testing. Desktop filesystem paths
must not be treated as Android content URIs. No Android APK is delivered yet.

## Build on this development machine

The initial build tools could not write in the Documents project directory.
The verified build was produced in a temporary mirror at
`C:/Users/k1ker/AppData/Local/Temp/ihtd-build`, using the Flutter SDK at
`C:/Users/k1ker/AppData/Local/Temp/ihtd-toolchain/flutter`. The source and
portable release were copied back to this repository. These temporary paths
are not required at runtime. No system security settings were changed.
