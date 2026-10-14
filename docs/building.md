# Build and test IHTD

Follow [shared app architecture and development workflow](shared-app-architecture.md)
when changing general behavior or UI. The
[cross-platform save migration plan](cross-platform-save-plan.md) describes the
shared coordinator and platform adapter boundaries; do not infer physical
platform acceptance from one platform's tests.

See [development and releases](development-workflow.md) for branch policy,
version validation, reusable platform CI, and the coordinated draft release.
`app/pubspec.yaml` controls package versions; installation files in packaging/
are templates rendered when packaging. Full CI artifacts are available for PRs
into master and manual runs; development PRs run faster tests. Ordinary branch
pushes/merges trigger no duplicate build. Matching version tags create a
combined draft prerelease. Testing artifacts are retained for 14 days.

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
./scripts/install-inno-setup.ps1
$env:IHTD_ISCC = Join-Path $env:LOCALAPPDATA 'IHTD-BuildTools\InnoSetup-6.4.3\ISCC.exe'
./scripts/package-windows.ps1
```

The result is `app/build/windows/x64/runner/Release/ihtd.exe`. Distribute the
whole Release directory, including its data directory and DLLs. Packaging adds
Visual Studio's licensed x64 redistributable runtime DLLs to both packages.
It creates `dist/windows/IHTD-X.Y.Z-windows-x64-setup.exe`, the portable ZIP,
installation instructions and `SHA256SUMS`. The per-user Inno Setup installer
supports upgrades, uninstall, shortcuts and optional `.ihtd` registration while
retaining user data. Both packages are currently unsigned.
The Windows workflow runs the build, storage/UI tests and release launch checks,
then tests installation, upgrade, uninstall and preservation on a native Windows
Server 2022 runner before uploading artifacts. It can be dispatched manually
for Windows alone. The release coordinator attaches both packages to the draft
on a version tag. See [Windows packaging](../packaging/windows/README.md).
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
flutter test test
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

Unlink/Delete tests cover actual root/parent placements, shared cascades,
stale/cancelled confirmation, deleted-container view rules and pending external
publication. `test/item_removal_test.dart` checks shared interaction and warning
presentation; the desktop integration test exercises real Rust removal, reopen
and disconnected-file recovery. Follow [physical removal acceptance](unlink-delete-acceptance.md)
for the Pixel, Windows and Fedora checks. Run native integration tests and
release APK builds sequentially in a shared checkout; Flutter regenerates plugin
registration for other targets as well. Use the normal dependency refresh for
the final APK after integration tests so test-only plugins are excluded.

Expression-editor coverage lives in `test/rule_draft_test.dart` and
`test/view_expression_test.dart`: infix scope, projection compatibility,
connector changes, empty slots, form cancellation, rapid field/option edits,
duplicate references, stale/queued collection changes and responsive layouts.
Native integration verifies nested-tag-OR creation hints across editor save and
reopen, task creation and deleted-container repair. Follow
[physical expression-editor acceptance](view-expression-editor-acceptance.md).
Optional host screenshots can be captured by running the view-expression tests
with `--dart-define=EXPRESSION_FONT=/absolute/path/to/a/font.ttf` and
`--dart-define=EXPRESSION_CAPTURE=/absolute/output/directory`; these are host
paint checks, not physical phone acceptance.

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

The output is `app/build/app/outputs/flutter-apk/app-release.apk`, a development
test/candidate APK. `app/rust/build.rs` sets Android's native linker page size
independently of machine-local configuration. `scripts/verify-android-apk.py`
checks every packaged ELF LOAD segment for at least 16 KB alignment; ZIP
alignment is checked separately. Run the ELF check before signing any APK.
Tagged releases re-sign that candidate in the protected
`android-release` environment and verify the pinned public certificate before
uploading the final APK. See [permanent signing](android-signing.md) for owner
backups, GitHub secret setup and local signing. Do not put private keys/passwords
in Git. Secrets activation, owner backup and physical update testing remain
required before declaring durable signing complete.

The Android UI opens/creates files through the system document picker. Private
working copies and the current document binding survive ordinary process
restart. Changes are checked against provider content before saving and verified
afterward. On a save conflict, use **Save a copy as** to preserve edits and then
reopen the desired document. External changes are reported rather than silently
overwritten; automatic provider reload is not part of this first milestone.
Export important documents before uninstalling or clearing application data.

Android provider checks live in `DocumentWriterTest` (run `:app:testDebugUnitTest`
from `app/android` with Gradle). Flutter storage-adapter tests run with
`flutter test test` from `app`, including controller/popup regression checks.
See [document-saving phone acceptance](document-save-phone-test.md) for the
rename, conflict, reconnection, recovery and diagnostic-export test sequence.
Use [the implementation plan](document-save-recovery-plan.md) for design context.
The shared save flow is covered by `test/document_contract_test.dart` on both
adapter types and by the real rename/reconnect sequence in the desktop
integration test. Follow [shared platform acceptance](shared-saving-acceptance.md)
for the build 8 migration on Pixel, Windows and Fedora. Python release tests also
enforce shared UI/policy import boundaries.
The narrow-screen interaction check is `integration_test/phone_layout_test.dart`;
it can run on the Linux host with `-d linux`, but does not exercise Android's
document providers. Responsive editor and rendered-surface checks are in
`test/layout_polish_test.dart`. Follow [layout acceptance](layout-polish-acceptance.md)
for Pixel system-bar/keyboard and native desktop scaling checks. In the restricted cloud workspace, after an APK build,
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
