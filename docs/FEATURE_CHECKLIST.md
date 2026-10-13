# Feature checklist

Updated 2026-10-13 for the Android first milestone and agreed release/update
workflow. Unchecked suggestions are not approved requirements unless they are
listed under "Agreed release and update work"; clarify their behavior before
implementing them.

## Remaining agreed work

- [x] Allow moving a task/folder into its own descendant by promoting its direct
  children to the dragged placement's former parent/top level, preserving their
  subtrees and shared IDs. Verify ordering, completion and phone drag acceptance.
- [ ] Fedora: build, test, and provide a runnable Linux package; verify on laptop.
  - [x] Prepare Fedora RPM and portable-bundle build definitions.
  - [x] Unblock the Linux build environment (Fedora 44 under updated WSL).
  - [x] Pass 47 Rust tests, Flutter analysis, and Linux UI integration test.
  - [x] Build RPM/portable packages and verify installed release launch.
  - [ ] Verify on the laptop: file picker, Wayland/scaling, and rclone mount.
- [ ] Android: Google Pixel 9 Pro running GrapheneOS is the first phone target.
  - [ ] Confirm the phone's installed Android version (minimum API 35/Android 15).
  - [x] Choose direct editing through Android's Storage Access Framework (SAF)
    with private working copies and local recovery.
  - [x] Build an ARM64 APK with the shared Rust model and bundled SQLite.
  - [x] Verify native libraries and APK packaging support 16 KB page sizes.
  - [x] Implement collection creation, reopening, save-copy and export on Android;
    never pass a `content://` URI to Rust as a filesystem path.
  - [ ] Verify those document actions through Files on the actual phone.
  - [ ] Preserve pending edits and recovery copies across backgrounding, screen
    lock and process restart; exercise failed saves and revoked file access.
  - [ ] Adapt touch scrolling, dragging, keyboard/insets, back navigation and
    narrow-screen editors, including large text and portrait/landscape.
  - [x] Pass Flutter analysis, six document-adapter tests, five native provider
    checks, 47 Rust tests and both host UI integration tests.
  - [ ] Verify installation, launch and document round trips on the actual Pixel
    with GrapheneOS default settings.
  - [ ] Verify core operation without Google Play services or network access;
    use scoped document grants rather than broad storage permissions.
  - [ ] Define durable release signing and test an APK update preserving data.
    Development-signed APKs must be clearly labelled as test builds.
  - [x] Document installation, file transfer/backup and any remaining limitations.
  - [ ] Follow up with automatic external-provider reload; the first milestone
    reports external changes and requires reopening or saving a separate copy.
- [ ] Design refinement after using the prototype, as originally planned.
  These are areas to review together, not a requirement to redesign everything.
  - [ ] Layout: sidebar/details-panel sizes, spacing, and information density.
  - [ ] Hierarchy clarity: indentation, connecting lines, task/folder icons,
    and indicators for shared items.
  - [ ] Visual style: colours, fonts, button styles, and light/dark themes.
  - [ ] Interactions: clearer drag-and-drop targets, access to common actions,
    and keyboard navigation.
  - [ ] Settings and filters: make completion inheritance, visibility options,
    and complex filters easier to understand.
  - [ ] Feedback: clearer saving/saved indicators, errors, confirmations,
    and empty views.
  - [ ] Smaller screens: adapt layouts for smaller desktop windows and,
    later, phones.
- [ ] Version/change history (later idea): decide how to inspect and restore
  earlier changes before implementing it.

## Agreed release and update work

Work through this section in dependency order. Do not offer automatic updates
until the corresponding packages have stable identities, signing, versioning,
and verification.

- [ ] Establish the shared development and release foundation.
  - [ ] Use `master` only for reviewed, releasable code and protect it from
    direct everyday changes.
  - [x] Create `development` for integration of the next version; merge
    short-lived `feature/*` and `fix/*` branches into it through pull requests.
  - [x] Document when to use temporary `release/x.y.z` stabilization branches
    and require their fixes to be merged back into `development`.
  - [x] Document `hotfix/*`: branch from `master`, merge into `master`, then
    merge the same fix back into `development`.
  - [x] Define one authoritative application version shared by Android,
    Windows, Fedora, package metadata, filenames, and release notes.
  - [x] Build every platform for an official release from the same immutable
    `vX.Y.Z` Git tag; do not maintain permanent platform source branches.
- [ ] Rework GitHub Actions around pull requests, `master`, and version tags.
  Implementation is in the coordinated `release.yml` workflow. Full native CI
  validation and a real tagged-release exercise must pass before checking off
  the operational release tasks below. Administrator branch protection remains
  pending because the integration credential cannot access that API.
  - [x] On development PRs, run Rust tests, Flutter analysis and Dart adapter
    tests; on master PRs, build/verify all platforms and retain testing artifacts
    for 14 days. Neither PR workflow publishes a release.
  - [x] Avoid duplicate builds on ordinary pushes/merges into development and
    master. Full builds run for master PRs, version tags, or manual requests.
  - [x] Update development's required check to `Development checks`; master
    continues requiring `All platforms validated`. Requires an administrator.
  - [x] On a `vX.Y.Z` tag, test and build Android, Windows, and Fedora from the
    tagged commit, then attach all verified outputs to one GitHub Release.
    v0.2.1 completed all jobs and draft uploads; downloaded checksums verified.
  - [ ] Publish a stable release only after every required platform succeeds;
    include generated release notes, installation instructions, package sizes,
    and SHA-256 checksums.
  - [ ] Keep downloadable application files in GitHub Releases. Use GitHub
    Packages only if a future registry/container use case requires it.
- [ ] Finish production-ready packages and signing.
  - [ ] Android: establish one backed-up permanent release-signing key, store
    it and its password as protected GitHub Actions secrets, document recovery
    ownership, and verify that a newly built APK updates an earlier public APK
    without losing app data.
    - [x] Generate an encrypted release keystore and pin its public SHA-256
      certificate in source; keep the password separate and private.
    - [x] Implement separate protected tag signing, certificate verification,
      fail-closed release assembly, and secure local generation/upload tools.
    - [ ] Owner downloads the keystore/password at home, keeps independent
      backups, and verifies recovery before activating public releases.
    - [ ] Administrator configures tag-only android-release environment and
      its three signing secrets; integration secret API returns HTTP 403.
    - [ ] Verify two permanent-key APKs on the actual Pixel as an in-place
      update, preserving working/recovery copies and document grants.
  - [ ] Android: publish a clearly named ARM64 APK compatible with the Pixel 9
    Pro/GrapheneOS target and verify its signature and 16 KB alignment.
  - [ ] Windows: add an Inno Setup `.exe` installer while retaining the complete
    portable `.zip` bundle.
    - [x] Implement per-user setup, shared-version packaging and EXE/ZIP release
      assembly with checksums; include app-local redistributable runtime DLLs.
    - [ ] Pass the native Windows installer verification workflow.
    - [ ] Verify the interactive wizard and Explorer/default-app behavior on
      an actual Windows 11 PC before stable publication.
  - [ ] Windows: make the installer support upgrades, clean uninstall, Start
    Menu integration, optional desktop shortcut, preserved user data, and
    `.ihtd` file association.
    - [x] Implement stable upgrade identity, recorded-file uninstall, shortcuts,
      optional Open-with registration and startup document loading.
    - [ ] Verify upgrade/removal and real collection/recovery preservation on
      the native Windows runner; physical Windows 11 validation also remains.
  - [ ] Windows: add trusted code signing before automatically executing a
    downloaded installer; consider MSIX later only for Store/enterprise needs.
  - [ ] Fedora: retain the installable `.rpm` and optional portable `.tar.gz`,
    with desktop/icon integration, clean upgrade/removal, and `.ihtd`
    association.
  - [ ] Fedora: sign the RPM and document verification; later decide whether
    public usage justifies hosting a signed DNF repository.
- [ ] Add a shared, privacy-conscious update experience.
  - [ ] Check the latest compatible GitHub release infrequently, compare its
    semantic version with the installed version, and show a small update icon
    only when a newer release is available.
  - [ ] Add an update screen with version, release notes, download size, and a
    user-confirmed action; also provide **Check for updates** and an option to
    disable automatic checks.
  - [ ] Keep stable releases as the default channel; expose development builds
    only through an explicit opt-in if that channel is added.
  - [ ] Verify downloaded metadata/package authenticity before offering an
    install action, and show useful offline, download, and verification errors.
- [ ] Implement the platform-specific update handoff.
  - [ ] Android/GrapheneOS: download the signed ARM64 APK and hand it to the
    system package installer; explain the one-time "install unknown apps"
    permission and require Android's normal user confirmation.
  - [ ] Android: confirm an update preserves app data, retained document grants,
    working copies, and recovery data on the physical Pixel.
  - [ ] Windows: first provide a guided download/open of the signed setup EXE;
    later add verified download, graceful app shutdown, installer launch, and
    restart if that flow proves reliable.
  - [ ] Fedora: initially open/download the signed RPM and hand installation to
    Fedora's graphical package tooling rather than overwriting package-owned
    files from inside IHTD.
  - [ ] Fedora: if a signed DNF repository is introduced, let DNF/GNOME Software
    provide normal system updates; keep portable `.tar.gz` updates manual.

## Optional features to discuss

- [ ] Delete items everywhere, clearly distinguished from removing one placement;
  decide how shared subitems and recovery/trash should behave.
- [ ] Undo/redo for edits, moves, and completion changes.
- [ ] Quick search without creating a saved filter view.
- [ ] Import exported JSON, with rules for restoring versus merging collections.
- [ ] Tag management: rename, delete, and optionally merge tags in the interface.
- [ ] A recovery screen for finding and restoring the local recovery snapshots.
- [ ] Convenience controls: keyboard shortcuts, multi-selection, and bulk actions.

Already implemented: shared IDs and arbitrary-depth hierarchy, task/folder
conversion, completion inheritance, per-view visibility, saved filters,
notes/dates/priorities/tags, portable .ihtd files, autosave/external reload,
JSON/Markdown/CSV exports, and drag-and-drop moves/reordering.

Built-in cloud integration and concurrent editing remain outside the agreed
prototype scope. Normal filesystem mounts/sync clients provide file access.
