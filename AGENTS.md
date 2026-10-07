# IHTD development

Read `REQUIREMENTS.md`, `docs/FEATURE_CHECKLIST.md`, and `docs/building.md`
before changing behavior. Ask the user when product semantics are unclear.

## Project

- Flutter 3.47.5 / Dart 3.13.4 UI in `app/`, shared Rust model in
  `crates/ihtd_core`, storage/application commands in `crates/ihtd_app`.
- Flutter Rust Bridge 2.13.0; bridge toolchain Rust 1.93.1 is pinned in
  `app/rust/rust-toolchain.toml`. Keep generated bindings consistent with APIs.
- Windows 11 and Fedora 44 x86-64 desktop prototypes work. Android is a future
  phase: scaffold exists, but document access and phone UX are not complete.
- Items have unique IDs and shared placements in an acyclic graph. Dragging
  moves only the grabbed placement. Do not duplicate shared item state.
- Collections use schema 2 `.ihtd` files with schema 1 migration. Preserve
  compatibility and atomic-save/external-change handling.

## Verification

- Core/storage: `cargo test --workspace --locked` (47 tests at this baseline).
- UI: inside `app`, run `flutter pub get`, then
  `flutter analyze lib integration_test/app_test.dart`.
- Linux UI: `GDK_BACKEND=x11 dbus-run-session -- xvfb-run -a flutter test integration_test/app_test.dart -d linux`.
- Release: `flutter build linux --release` or `flutter build windows --release`
  on the corresponding OS. Keep the complete generated bundle together.
- Fedora packaging lives in `packaging/fedora`. Its setup/verification scripts
  target a disposable Fedora environment with the repo copied to `/workspace`;
  do not execute them directly on another distribution or everyday workstation.
- Linux and Windows checks passed for 0.2.0. Physical Fedora laptop checks for
  Wayland, scaling, file picking, and the rclone mount remain on the checklist.

## Working across computers

- Keep requirements, checklist, and build instructions updated so a fresh
  session can resume without the original chat history.
- Commit source and lockfiles. Keep personal `.ihtd` data, credentials, build
  outputs, SDKs, and machine-local settings out of Git.
- Never overwrite uncommitted work to synchronize machines. Use branches and
  reviewable commits. Cloud changes must be committed/pushed before a local
  checkout can receive them.
- Respect the user's remaining-usage reserve: stop before the five-hour
  allowance falls below 10% when usage information is available. If unavailable,
  say so rather than claiming that the reserve is being monitored.
