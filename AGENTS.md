# IHTD development

Read `REQUIREMENTS.md`, `docs/FEATURE_CHECKLIST.md`, and `docs/building.md`
before changing behavior. Ask the user when product semantics are unclear.

## Shared-first implementation

Read [shared app architecture](docs/shared-app-architecture.md) before changing
behavior or UI. Implement general product functionality once in shared Rust/
Flutter code for Android, Windows and Linux. Platform adapters provide file/OS
access and typed observations; shared policy owns save/recovery decisions,
severity, messages and confirmations. Select adapters at composition/bootstrap;
shared UI must not depend on Android storage or branch on operating-system names.
Use layout constraints, text scale, insets and input capabilities for responsive
design. Explain necessary platform exceptions in the PR and update requirements,
checklist and shared/adapter tests. Android-only implementation is not evidence
of cross-platform completion. Follow the implemented
[shared save boundaries and acceptance plan](docs/cross-platform-save-plan.md).

## Project

- Flutter 3.47.5 / Dart 3.13.4 UI in `app/`, shared Rust model in
  `crates/ihtd_core`, storage/application commands in `crates/ihtd_app`.
- Flutter Rust Bridge 2.13.0; bridge toolchain Rust 1.93.1 is pinned in
  `app/rust/rust-toolchain.toml`. Keep generated bindings consistent with APIs.
- The owner-clarified [Changes.docx backlog](docs/changes-2026-10-28.md) is
  approved. The migration foundation is an implementation candidate; the other
  features remain pending except the shared item-draft/Save/Cancel and collection
  settings candidates. Read `docs/collection-settings.md` before adding indicators
  or tag suggestions: Rust owns defaults/inheritance; per-field resets must resume
  inheritance, and settings commands preserve item drafts/file-save barriers.
  Read `docs/item-editor-drafts.md`: private drafts never auto-commit on typing,
  disposal/backgrounding or model refresh. Use controller resolution guards for
  navigation/separate actions, preserve the owning working path plus UUID, and
  retain private recovery/Save receipts. It revises linking/removal/copying
  and other UI/model behavior described below. Read it and the checklist before
  implementing those tasks; older passing checks describe the baseline only.
  Ask about new ambiguities rather than inventing product behavior.
  Any conversion of existing stored data must first implement its migration
  safety gate: verified backup beside the original/authorized backup folder,
  staged validation, guarded publication and automatic redacted failure logs.
  Follow `docs/migration-safety.md`: shared MigrationSafety owns policy, Rust owns
  read-only probes/candidate validation, adapters supply backup access. Current
  schema-2 files need no conversion; future semantic/schema changes must extend
  the explicit plan and preservation tests. Physical upgrade acceptance is pending.
- Windows 11 and Fedora 44 x86-64 desktop prototypes work. Android development
  targets Pixel 9 Pro / GrapheneOS first (ARM64, API 35+). SAF uses private working
  copies and local recovery; physical phone validation remains outstanding.
- Items have unique IDs and shared placements in an acyclic graph. Dragging
  moves only the grabbed placement. Descendant moves first promote direct
  children to its former parent/root; children are shared across placements.
  Do not duplicate shared item state.
- The owner-approved view-rule redesign is an infix expression editor, with
  scoped circular pluses and Option-A narrow wrapping, not group-heading cards.
  Follow `docs/view-expression-editor-plan.md`; preserve matching AND creation
  hints when displaying flattened AND/OR chains. Shared implementation is complete;
  physical acceptance remains pending. Use `docs/view-expression-editor-acceptance.md`.
- Shared linking/copying/removal is in `crates/ihtd_core/src/hierarchy.rs`.
  Read `docs/link-copy-removal.md` and the later owner specification: count full
  hierarchy appearances, offer explicit global Delete and local Unlink, and use
  revision/path-bound previews. A linked ancestor blocks direct child Unlink;
  only the confirmed full independent replacement can isolate that occurrence.
  Copy from a frozen source, honor depth/reuse boundaries, preserve settings and
  deleted IDs, and use the shared controller/file-save safeguards. The historical
  removal helpers describe the old baseline; do not use them in new product UI.
- Collections use schema 2 `.ihtd` files with schema 1 migration. Preserve
  compatibility and atomic-save/external-change handling.
- App model sessions edit private working copies on all platforms. External
  reads/writes go through `DocumentSaveCoordinator` and typed adapters. Shared
  registry schema 3 migrates legacy Android metadata without deleting its
  working/recovery files. Do not bypass barriers with direct external model paths.
- Android release identity is pinned in `packaging/android/release-certificate.sha256`.
  The bridge's Android linker configuration in `app/rust/build.rs` and
  `scripts/verify-android-apk.py` enforce 16 KB ELF LOAD alignment. APK ZIP
  alignment alone is insufficient; verify both layers before handing over APKs.
  Follow `docs/android-signing.md`; never regenerate/replace the key casually or
  commit private signing files. The owner-approved key is stored privately outside
  Git pending owner home backups and protected GitHub environment activation.
- Windows setup lives in `packaging/windows/ihtd.iss`: preserve its permanent
  AppId and the existing `dev.ihtd` / `IHTD` support-directory identity. Packages
  include the installer and portable ZIP with app-local licensed runtime DLLs.
  Never add cleanup that deletes user collections or recovery data. Installer
  verification installs/uninstalls on disposable native CI runners only.

- Shared updates live in update_contract/catalog/coordinator and ui/app_updates.
  Native selection belongs only in update_composition; verify downloads before
  ready and before OS handoff. Never embed GitHub credentials or execute unsigned
  desktop installers. Preserve local-save barriers; follow docs/update-acceptance.md.

- Original IHTD source uses AGPL-3.0-only; preserve LICENSE/COPYRIGHT and third-party
  notices. Keep app/LICENSE identical to root LICENSE, retain source pointers in
  packages, and follow docs/licensing.md before distributing binaries.

## Verification

- Core/storage: `cargo test --workspace --locked` (67 tests at this baseline).
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

Follow [development and release policy](docs/development-workflow.md): normal
task branches target `development`; releases reach `master` through reviewed
pull requests. Version-tag releases build all platforms from one commit.

The user has explicitly authorized this default GitHub synchronization workflow
for future coding tasks in this repository:

1. At the start, inspect the current branch, upstream, and working-tree status.
   With a clean checkout, pull the upstream using `git pull --ff-only` before
   editing. If the checkout is dirty or histories have diverged, preserve all
   work and resolve the situation without overwriting changes or force-pushing.
2. Implement the requested changes and run the relevant checks.
3. At completion, stage all source/documentation changes belonging to the task,
   commit with a descriptive message, and push to the current branch's upstream.
   A new task branch should use the `codex/` prefix and get an upstream on push.
   A docs-only task does not require rerunning the app's full test suite.
4. Verify the push succeeded and report the commit and any remaining changes.
   If authentication, a conflict, or the usage reserve blocks completion, report
   the exact outstanding sync step. Never claim a failed push was successful.

These routine pulls, commits, and pushes do not need fresh user confirmation.
The source repository is public `https://github.com/Plexyer/ihtd.git`; its
initial default branch is `master`. This workflow synchronizes local work with
GitHub; it does not move a local Codex session to cloud execution.

On the original Windows workstation, Git Credential Manager is already signed
in. If the inherited helper selector stalls, use the existing manager directly:
`git -c credential.helper= -c credential.helper=manager <pull-or-push-command>`.
Never print credentials or store them in the repository.

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
