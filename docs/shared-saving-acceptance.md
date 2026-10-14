# Shared saving acceptance on Android, Windows and Fedora

Candidate application version is 0.2.2, Android build 8. All platforms use the
same save coordinator, warning popup, confirmation policy and private diagnostic
export. Their adapters report different available facts; an undetectable rename
is reported as lost access rather than a guessed filename.

Use disposable collections and keep external backups. Install candidates through
the existing supported update paths; do not uninstall Android or clear app data
to test a signing-compatible update. Stable publication remains separate.

## Common tests on each physical platform

1. Create/open a collection through the native picker. Add recognizable items,
   verify Saved to file, and independently reopen the external .ihtd document.
2. Background/minimize the app and rename the selected document. Return and
   expect yellow. Android may report a precise rename through a retained URI;
   desktop may report unavailable access to the old path. Neither should guess
   a new location or silently recreate the original filename.
3. Edit a task, open its editor, change views, open/dismiss warning details and
   wait for several checks. Pending changes must remain yellow and the external
   document must remain unchanged until explicit reconnection/confirmation.
4. Restart with pending work. Verify the local edits and save barrier survive.
   Choose the renamed file to reconnect, cancel once, then confirm the named
   destination. Verify a read-back-confirmed save and correct displayed name.
5. Change the external document's contents independently. Local edits must not
   overwrite them. Save a copy, or explicitly reopen the external version while
   preserving the former working copy in Advanced details → Retained working copies.
6. Delete/move the original and put another same-named file there. When stable
   identity is available, expect a replacement warning even for equal contents.
   Never automatically attach pending edits to a replacement. Explicit selection
   still requires fresh approval and matching confirmed-baseline contents.
7. Test read-only/revoked access or an unavailable chosen provider/mount. Expect
   yellow access warnings or red confirmed write failures as applicable. Verify
   retained work, no repeated automatic writes and retry/save-copy choices.
8. Export default diagnostics: no filenames, paths, full references, task data
   or raw exceptions. Extended file metadata requires separate consent; cancel
   both consent and destination pickers once and verify document state survives.
9. Test narrow/large windows, large text, keyboard and touch/mouse use. Warning
   colors must have readable text/icons and dialog actions must remain reachable.

## Platform-specific acceptance

- Pixel/GrapheneOS: update from permanent-key build 7 (or 5/6), preserving document
  grants, old Android working copies and retained archives. Verify migration to
  shared state, lock/background/restart and offline operation without Play services.
- Windows: install/upgrade normally, launch a .ihtd file through Explorer and
  verify Unicode/space-containing paths, read-only files, retained copies and
  no change to the existing support-directory identity.
- Fedora: verify Wayland/scaling, native file pickers and the chosen rclone/sync
  mount. A mount without reliable identity/atomic replacement may expose fewer
  facts or a write failure; it must still preserve edits and avoid false success.

Do not deliberately fill a daily-use disk or inject partial writes on important
collections. Automated fault tests cover these cases; use a disposable device or
fixture for additional native fault acceptance. Record pass/fail, platform/provider
versions and diagnostic codes. Host/CI tests do not replace these physical checks.
