# Collection settings and indicator inheritance

Implementation candidate for step 3 (specification item 7), 2026-10-29.
The [approved specification](changes-2026-10-28.md#7-collection-settings) is the
contract. This step provides the stored settings and shared controls needed by
the later tag-picker and summary-indicator tasks; it does not implement those
consumers, their metrics, tag-usage history or the priority-icon redesign.

## Controls and ownership

Settings in the top-right menu opens Collection Settings for the active collection.
Existing unfinished item edits first follow Save / Discard / Keep editing.
The settings form has Save settings and Cancel; changes remain isolated until Save.
Validation failures retain the choices. Device-specific update preferences remain
separate and are not copied into the collection.

- Suggested unselected tags defaults to 5, accepts non-negative whole numbers;
  0 disables suggestions while retaining selected tags in the future picker.
- Tag usage half-life defaults to 3 days, accepts positive whole days. This stores
  the period, not popularity events or a ranking calculated from existing tags.
- Indicator defaults: Total and High-priority count on; completed/total, Medium,
  Low and next due date off. The ratio is an independent preference and replaces
  the plain count when Total is enabled; it does not turn Total on implicitly.

Summary indicator settings in each existing task/folder editor opens two layers:
This parent in this view and expandable Shared parent defaults. Both sets are
staged and saved atomically with Save settings. Each individual control offers
Use inherited setting, On or Off and shows its effective value/source. Cancel
changes neither layer. These are separate presentation settings: saving them
does not commit unfinished item fields, and cancelling an item draft does not
undo a separately accepted settings change. Parents without children can be
configured in advance. These settings follow an item ID across its linked
appearances; they do not depend on a particular ancestor path.

Resolution for every indicator is independently:

1. Collection indicator default.
2. That parent's shared override, if present.
3. That parent's override in the selected view, if present.

An absent/null override inherits. An explicit false still overrides a true default.
Returning to Use inherited setting removes that one override and resumes following
later defaults. Changing one field never freezes the others. A parent's defaults
affect its own child-summary presentation, not defaults for descendant parents.
Visibility preferences retain their existing, separate inheritance rules.

## Shared implementation and save safeguards

`crates/ihtd_core/src/settings.rs` defines settings, defaults, validation, atomic
updates and `Document.resolved_indicators`. Future summary metrics must use that
resolution rather than inventing defaults or computing disabled metrics.
`ui/collection_settings.dart` supplies shared, responsive forms on Android,
Windows and Linux; it overlays staged values only to preview inheritance.
The snapshot supplies the complete collection defaults from Rust, so Flutter
has no separate hard-coded product defaults.

Collection saves compare the expected settings. Parent/view saves compare both
expected override maps, then update only indicator fields; visibility settings
and other views remain intact. Missing items/views and stale settings fail without
partial mutation. Controller guards compare the working path plus document UUID
inside its command queue, preventing a form from writing into another collection
or another working copy sharing a UUID. All accepted mutations still use
DocumentSaveCoordinator and its normal external identity/reconnection barriers.
Settings may be committed privately while external publication stays pending.

Deleting an item also removes its shared indicator defaults; deletion's existing
view-preference cleanup removes view overrides. Unlink preserves the settings
for the surviving shared item. Renaming or converting an item retains them.

## Compatibility and migration decision

This feature needs no schema or semantic conversion of existing user data.
Collections stay schema 2. Optional SQLite metadata keys `collection_settings`
and `parent_indicator_defaults` store the new data; per-view overrides live in
the existing container-preference JSON's optional `indicators` field. Absent
metadata/fields resolve to the approved defaults in memory. Opening or inspecting
an existing schema-2 collection does not rewrite it or create a migration backup.
Saving accepted edits stores the new settings alongside all existing fields.

Default-valued document fields and empty overrides are omitted from the serialized
document projection, preserving existing item-draft semantic Save receipts and
view baselines when the feature has not been configured. Malformed or unsupported
settings are rejected instead of silently replaced. Existing schema-1 collections
still go through the verified-backup migration gate before mutable open. Any later
conversion must extend that gate and its preservation tests; this change does not
relax it. Older app versions do not know these new preferences, so do not use an
older app to edit a collection configured with them if you need to retain them.

## Verification and acceptance

Automated tests cover per-indicator inheritance/reset, separate views, no ancestor
leakage, stale/invalid/missing owners, preserving visibility and deletion cleanup.
Frozen distributed schema-2 SQLite data proves read-only default loading, then
settings save/reopen equality for existing items, fields, tags, shared links,
orders, views and preferences. Unknown/malformed settings are not silently reset.

Flutter tests cover Save/Cancel, number validation, parent/view settings independent
of unfinished drafts, Keep editing, cross-collection ownership and short/narrow,
large-text layouts. Native `integration_test/collection_settings_test.dart` uses
real Rust/Flutter, distributed data, file publication, rename/disconnection and
restart; the Windows and Fedora workflows run the same integration.

Physical acceptance remains open on Pixel/GrapheneOS, Samsung, Windows and Fedora:

1. Upgrade with a real existing collection, verify its contents and that Settings
   starts at the approved defaults. Verify opening alone changes no file.
2. Save settings, close/reopen the app and open the collection on another platform;
   verify the preferences travel with it, including linked parents and two views.
3. Set different shared/view choices, change a collection default, and verify only
   inherited fields follow it. Remove an override and verify inheritance resumes.
4. Use Cancel, invalid numbers, keyboard/rotation, large text and a short window;
   verify controls/actions remain reachable without losing choices.
5. Leave an item draft unfinished, save separate indicator preferences, then
   cancel the item draft. Preserve the preferences and the item's saved text.
6. Rename/revoke the external file while Settings is open; keep the established
   warning/recovery behavior and retain accepted choices locally without falsely
   claiming publication. A different open working copy must never receive them.

The later indicators/tag-picker tasks need their own functional/device checks.
No version bump or release is included in this task.

Cloud verification, 2026-10-29: static analysis, 176 Flutter tests, 83 Rust tests
and 17 Python checks passed. The settings, phone-layout and item-draft-recovery
integrations passed with real Rust/Flutter on the Linux host. An ARM64 release
APK built and passed the four-library 16 KB ELF and APK ZIP-alignment checks.
The final settings widget checks also passed after source-label/layout refinements.
Native Windows/Fedora CI and the physical acceptance above remain separate.
