# IHTD

A desktop-first todo prototype with a Flutter interface and a shared Rust core.

## Run on Windows 11

Open **dist/windows/IHTD-0.2.0/ihtd.exe**, or extract **dist/IHTD-0.2.0-windows-x64.zip**
and run ihtd.exe inside the extracted folder. Keep the DLLs and data directory
beside the executable. No Flutter or Rust installation is needed to run it.
On another PC, install Microsoft's Visual C++ x64 Redistributable if Windows
reports a missing VCRUNTIME/MSVCP DLL.

Choose **Create collection** to create a new .ihtd file, or **Open file** to
select an existing one. Use an unused filename when creating a collection,
saving a copy, or exporting. The prototype never overwrites an existing file
through those commands.

## Using the prototype

- Drag an item onto a task or folder to move it inside. Drop between rows to
  reorder or use **Drop here to move to the top level** to move it out of a
  container. Only the dragged parent placement moves; shared locations and
  subitems are preserved for ordinary moves. Dropping into a descendant first
  promotes direct children to the former parent/top level, then moves the item
  under the destination. Dropping onto an existing placement merges the
  placements without duplicating the item. Order is shared across views.
- Existing .ihtd files open normally. Saving with version 0.2 upgrades the
  document format to retain ordering and shared top-level placements; use this
  updated app on every device that opens that document.

- Add tasks or folders, then click an item to edit its title, plain-text notes,
  date-only due date, priority (None / Low / Medium / High), and tags.
- In an item's details, add subitems or choose **Link existing** to reuse an
  item under another parent. IDs distinguish items with identical titles.
- Automatic completion passes down through folders. Shared descendants remain
  governed by every enabled ancestor; the details show the enforcing task IDs.
  Completing a branch manually asks before completing all descendant tasks.
- Create saved views with nested AND, OR, XOR, and NOT conditions. Filter by
  title/notes, tags, parent membership, due date, priority, type, or completion.
  Creation fills deterministic defaults and requires the full filter to match.
- Each container has visibility settings for the selected view. Completed
  children hide by default; inheritance is optional and can be overridden.
  Folders can be hidden and optionally reappear when a new task is added below.
- **Completed** retains unfinished ancestors needed to navigate the hierarchy.
- The top-right file menu offers new/open, save a copy, retry, and exports.
  JSON preserves the complete model; Markdown is for reading and CSV for tables.
  Export includes the whole collection, regardless of the selected view.

Changes save automatically. Text edits save after a short typing pause (650 ms);
**Save now** flushes immediately. Changing the selected item/document or making
an export flushes the current editor first. Normal desktop exit requests also
flush it. An error keeps the draft available instead of silently overwriting
an externally changed item.

A single .ihtd file holds items, relationships, tags, and saved views. Use local,
USB, or mounted/synced folders, including an rclone mount. The app checks the
open file every three seconds and when it regains focus. A newer valid revision
reloads automatically. Use one editing device at a time; concurrent merging and
history are outside this prototype. “Saved to file” describes the local
filesystem write, not completion of a cloud upload.

## Platforms and validation

Download the compiled Windows ZIP and Fedora RPM/portable bundle from the
[IHTD 0.2.0 release](https://github.com/Plexyer/ihtd/releases/tag/v0.2.0).
The private release includes SHA-256 checksums and Fedora install instructions.
Source and build scripts are tracked in Git; compiled packages are release assets.

Version 0.2.1 is being prepared on separate Android, Windows and Fedora branches.
It includes Android document access, status-bar spacing and descendant moves.
The existing 0.2.0 downloads do not include these changes. Build results and
pull-request preparation are recorded in [release preparation](docs/release-0.2.1.md).

Windows x64 was built and exercised on this computer. Rust domain/storage tests
and a real Windows Flutter integration test passed. Fedora 44 x86-64 packages
are in `dist/fedora`: an RPM and a portable tar.gz bundle. All 47 Rust tests,
Flutter analysis, and the Linux UI integration test passed in Fedora under WSL.
The RPM was installed and its release launched as an ordinary Linux user.
See [Fedora installation instructions](packaging/fedora/INSTALL.md). Physical
laptop testing (including Wayland, scaling, and the rclone mount) remains. Android
reuses the Rust model and Flutter widgets; its first phone milestone is described
below and still needs physical device testing.

See [build instructions](docs/building.md), [requirements](REQUIREMENTS.md),
and [storage design](docs/document-storage.md).
Track remaining work and undecided ideas in the [feature checklist](docs/FEATURE_CHECKLIST.md).

Android development now targets **Google Pixel 9 Pro with GrapheneOS** first
(ARM64, Android 15 or newer). The first milestone adds system document-picker
access, private recovery copies, and touch/keyboard adaptations. See the
[Android build and phone-test instructions](docs/building.md#android-pixel-9-pro--grapheneos).
Physical phone validation and durable release signing are still pending.

## Source layout

- crates/ihtd_core: item graph, metadata, completion, filters, view preferences.
- crates/ihtd_app: document commands, SQLite snapshots, outlines, exports.
- app/lib: Flutter interface and Riverpod controller.
- app/rust: flutter_rust_bridge entry point and generated bindings.
- app/windows, app/linux, app/android: platform runners.

The .ihtd format is SQLite with one stored record per item and independent
parent/child links. rusqlite owns persistence in Rust; a second Dart database
layer is unnecessary. Pub and Cargo lockfiles are included.

## Prototype limits

There is no built-in Google Drive login, history, concurrent-edit merge,
encryption, export-import UI, permanent item-deletion UI, or installer.
Removing a placement keeps the underlying item and other placements. There is
no product-imposed hierarchy depth limit, but available memory and the number
of displayed shared paths bound practical document size.
