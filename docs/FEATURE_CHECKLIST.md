# Feature checklist

Updated 2026-10-07 for version 0.2.0. Unchecked suggestions are not approved
requirements; clarify their behavior before implementing them.

## Remaining agreed work

- [ ] Fedora: build, test, and provide a runnable Linux package; verify on laptop.
  - [x] Prepare Fedora RPM and portable-bundle build definitions.
  - [x] Unblock the Linux build environment (Fedora 44 under updated WSL).
  - [x] Pass 47 Rust tests, Flutter analysis, and Linux UI integration test.
  - [x] Build RPM/portable packages and verify installed release launch.
  - [ ] Verify on the laptop: file picker, Wayland/scaling, and rclone mount.
- [ ] Android (later phase): phone interface, document picker/storage access,
  and a tested APK using the shared model.
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
