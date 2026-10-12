# Feature checklist

Updated 2026-10-08 for the Android first milestone. Unchecked suggestions are not approved
requirements; clarify their behavior before implementing them.

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
