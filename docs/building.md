# Build and test IHTD

See [development and releases](development-workflow.md) for branch policy,
version validation, reusable platform CI, and the coordinated draft release.
`app/pubspec.yaml` controls package versions; installation files in packaging/
are templates rendered when packaging. CI artifacts are available after PR and
branch builds; only matching version tags create a combined draft prerelease.

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
./scripts/package-windows.ps1
```

The result is `app/build/windows/x64/runner/Release/ihtd.exe`. Distribute the
whole Release directory, including its data directory and DLLs. On a machine
without the C++ runtime, install Microsoft's x64 Visual C++ Redistributable.
Packaging creates `dist/windows/IHTD-0.2.1-windows-x64.zip`, installation
instructions and `SHA256SUMS`. The Windows release workflow runs the build,
storage tests, both UI integration tests and a release-launch check on a native
Windows 2022 runner, then uploads artifacts and a draft prerelease.
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
Descendant-move checks cover promotion to the former parent/top level, shared
placements, sibling order, stale targets and completion. The phone integration
test exercises a long-press drop into a nested descendant through the UI.

If you change the public Rust bridge API, install codegen version 2.13.0 and
run `flutter_rust_bridge_codegen generate` inside app. Its version must match
the Rust and Dart bridge packages.

## Android: Pixel 9 Pro / GrapheneOS

The first target is ARM64, Android 15 (API 35) or newer. Use the same Flutter and
Rust versions above, JDK 21, Android platform 36, build-tools 36.0.0 and NDK
28.2.13676358. Install the `aarch64-linux-android` Rust target. Set `ANDROID_HOME`
to your SDK directory and ensure Java is on PATH. Then run:

```sh
bash scripts/build-android.sh
```

The output is `app/build/app/outputs/flutter-apk/app-release.apk`. The current
scaffold uses a development signing key even in release mode: this is a test
APK, not a production release. Do not put keystores or passwords in Git. Durable
release signing and update verification remain checklist items.

The Android UI opens/creates files through the system document picker. Private
working copies and the current document binding survive ordinary process
restart. Changes are checked against provider content before saving and verified
afterward. On a save conflict, use **Save a copy as** to preserve edits and then
reopen the desired document. External changes are reported rather than silently
overwritten; automatic provider reload is not part of this first milestone.
Export important documents before uninstalling or clearing application data.

Android provider checks live in `DocumentWriterTest` (run `:app:testDebugUnitTest`
from `app/android` with Gradle). Flutter storage-adapter tests run with
`flutter test test/android_documents_test.dart` from `app`.
The narrow-screen interaction check is `integration_test/phone_layout_test.dart`;
it can run on the Linux host with `-d linux`, but does not exercise Android's
document providers. In the restricted cloud workspace, after an APK build,
the JVM checks can skip `:app:compileFlutterBuildDebug` with Gradle's `-x` option
to avoid launching Flutter outside its writable-home wrapper.

To try the test APK, transfer it to the Pixel and open it in Files. Allow APK
installation for that source when Android prompts, then open IHTD. Start with a
new test collection in local Files, and import a copy of any important desktop
collection. Keep GrapheneOS protections enabled; neither Google Play services nor
network access is required by the core app. Keep exported copies outside IHTD's
private storage for backup. This development key is local to the build workspace;
do not assume a later build from another workspace can update this installation.

Cloud verification on 2026-10-08 passed 47 Rust tests, six Flutter document-adapter
tests, five Kotlin document-writer tests, Flutter analysis, and the existing
desktop and new narrow-screen integration tests on Linux. APK checks verify the
development signature, API 35 minimum, absence of internet/broad-storage
permissions, and 16 KB ZIP/native-library alignment. These are build and host
checks; physical Pixel/GrapheneOS validation is still outstanding.

On the actual Pixel, verify installation with default GrapheneOS protections,
creation/opening/export through Files, text edits and keyboard layout, touch
scrolling/long-press moves, lock/unlock and process restart, revoked document
access, external changes, and operation without Play services or network access.
Only providers installed on the phone can appear in its picker. Test local Files
first, then any chosen sync provider. Physical device checks cannot be replaced
by a successful APK build or desktop integration test.

## Build on this development machine

The initial build tools could not write in the Documents project directory.
The verified build was produced in a temporary mirror at
`C:/Users/k1ker/AppData/Local/Temp/ihtd-build`, using the Flutter SDK at
`C:/Users/k1ker/AppData/Local/Temp/ihtd-toolchain/flutter`. The source and
portable release were copied back to this repository. These temporary paths
are not required at runtime. No system security settings were changed.
