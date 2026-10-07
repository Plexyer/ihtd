# Changes

## Fedora package — 2026-10-07

- Released 0.2.0 packages for Fedora 44 x86-64: RPM with menu entry/icon, plus
  a portable tar.gz bundle and SHA-256 checksums.
- Corrected Linux plugin library lookup to use bundled libraries, removing
  references to the build machine from the packaged file-picker plugin.
- Verified 47 Rust tests, Flutter analysis, and the Linux UI integration test
  under Fedora/WSL. Installed the RPM, checked library dependencies and file
  integrity, and launched the release as an ordinary user under a virtual display.
- Physical Fedora laptop testing remains.

## 0.2.0 — 2026-10-03

- Drag tasks and folders onto containers to move them inside.
- Drop between rows to change their order, or on the top-level target to move
  a placement out of its parent. Dropping on a parent appends to its children.
- Highlight valid destinations and show a floating preview while dragging.
- Preserve IDs, subitems, and other shared placements. Reject circular moves.
- Save each move atomically and recompute automatic completion.
- Persist root order and shared top-level placements in document schema 2.
  Existing schema 1 files migrate when opened and upgrade on their next save.
- Keep the previous Windows build separate so an open app does not prevent
  installing the new portable release. Close the old app before opening the
  same document in version 0.2.

Validation: 47 Rust tests; Flutter static analysis; a Windows integration test
exercising actual drag gestures, shared placements, reordering, and file reopen.
