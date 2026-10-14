# IHTD prototype behavior

Updated 2026-10-08. This records the implemented prototype and the user's
clarifications; platform validation is listed separately in README.md.

## Model

Every task and folder has a positive document-local ID independent of its
title. Duplicate names are allowed. Items and ordered parent/child links are
stored separately; multiple parents reference the same underlying item and
children. Cycles are rejected. Tasks and folders both accept children and may
be converted without changing IDs or links. Converting to a folder removes
task completion settings; converting to a task starts unfinished.

## Moving items

Drag-and-drop moves only the dragged parent relationship or root placement.
Other parents and the item's subtree are preserved for ordinary moves. When
moving into a descendant, first detach all direct children and promote them to
the grabbed placement's former parent (or top level), preserving their order
and subtrees. Then attach the moved item under the destination. Children are
shared state: this detaches them from every placement of the moved item, while
preserving their other parent links. Existing promoted placements coalesce.
Root and sibling order persist, and moving onto an existing placement coalesces
the links. Moves are
atomic, reject cycles, and recompute completion. Ordering is document-wide.

## Completion

Folders are containers, with view-specific hide/reappear switches.
Tasks can explicitly enable automatic completion. This setting is also
enforced by enabled task ancestors, including across intervening folders and
all shared paths. Independent enabled ancestors must all release the task
before inherited automatic completion can be disabled. The highest enforcing
ancestor IDs are shown. Inheritance does not enable an unrelated parent of a
shared child. Local explicit settings persist when an inherited requirement
ends.

Leaf tasks are completed manually. An automatically completing task with task
descendants finishes only when those descendants finish. New or reopened
unfinished tasks reopen automatic ancestors. Manually completing a task with
unfinished descendants requires confirmation to complete the descendant
hierarchy everywhere those shared items occur.

## Views and creation

Saved filters support nested AND, OR, exactly-one XOR, and NOT; title and
plain-text notes comparisons; tags; direct/recursive container membership;
due-date comparisons and date presence; priorities; item kind; completion.
Text comparisons include contains, equals, starts/ends with, and negative
contains/equals, with optional case sensitivity. Digits in text are ordinary
searchable text. No custom numeric fields are introduced.

Simple tag OR creation applies all listed tags. Simple tag XOR chooses the
lowest tag ID. Text literals, such as notes containing invoice, are prefilled
where deterministic. Ambiguous constraints request user-entered values.
The entire filter must match before creation is committed; contradictory
conditions cannot create a partially matching item.

Completed children disappear from unfinished displays by default. Each
container has independent preferences in each saved view. Inheritance is
off by default, and descendants can explicitly override inherited visibility.
Inheritance follows the displayed parent path for shared placements.
Completed displays retain unfinished ancestors for context.

Folders have a hide switch and an independent reappear-on-new-task switch.
Hiding a folder does not complete its descendant tasks.

## Fields and files

Title, tags, plain-text notes, date-only due date, and priorities None / Low /
Medium / High. No custom fields.

One independent .ihtd file is open at a time. Native filesystem open/save
dialogs support local, removable, and mounted paths. Accepted mutations save
automatically; text typing is coalesced briefly. External revisions are reported
for explicit reopening, consistently across platforms; they do not silently
replace pending work. One editing device at a time, no history or merge in this prototype.
On desktop, a document path supplied at startup opens through the same
private-staging and guarded-publication flow; errors remain visible in the app. Windows setup
offers `.ihtd` Open-with registration while respecting the user's default app.

JSON exports IDs, relationships, all fields, tags, views, and preferences.
Markdown and CSV are readable/tabular convenience formats. The .ihtd document
remains the directly reopenable backup format.

## Platform scope

Windows 11 and Fedora desktop first. Flutter/Dart with Riverpod is shared
across desktop and future Android. Rust implements the domain and file
operations, connected by flutter_rust_bridge. SQLite is bundled through
rusqlite. Android packaging, document-provider integration, and phone testing
are now being developed first for a Google Pixel 9 Pro running GrapheneOS.

## Android first milestone

Target ARM64 and Android 15/API 35 or newer, matching the pinned Rust native
toolchain. Confirm the installed Android version during physical phone testing.
Core operation must not depend on Google Play services or a network connection.
Use GrapheneOS default security settings; do not require broad storage access.

The user chose direct document access through Android's Storage Access Framework
with private local recovery. Create/open uses the system document picker and
retains access to the selected URI. Rust works only on private filesystem copies.
After a local commit, compare the provider content with the previously read
content, publish the complete document, and verify the bytes by reading back.
Show failed/conflicting saves and keep local edits available for Retry or Save
a copy. Save-copy switches to the newly saved collection, as on desktop.
Reopen the retained working collection after process restart.

## Shared saving and recovery on all platforms

The same Flutter coordinator, warning UI, confirmation and diagnostic policy
applies on Android, Windows and Linux. Native adapters only supply file access
and structured observations/failures. All model editing uses private working
copies; the external file remains the direct-edit destination and is published
after coordinator checks. Desktop uses guarded atomic replacement and read-back
verification; Android uses provider conflict/read-back checks.

Desktop file identity uses Windows file IDs or Unix device/inode when available.
A replacement at the same path is reported even with identical contents.
Missing-path renames cannot always be located; reconnect through the picker
without silently recreating the old path. Explicitly selecting a replacement
can reconnect only with fresh approval and matching confirmed-baseline contents.
File metadata/capabilities and provider identities may be uncertain on mounts.

Shared registry schema 3 is stored under the unchanged application support
directory's documents folder. Legacy Android metadata is copied atomically;
existing working/recovery files and archives remain available and are not
deleted during migration. Persisted barriers survive restart and retained-copy
restoration. Physical update/mount acceptance must still be tested by the owner.

External publication and private commits have separate status. Inspect the
provider on resume, during foreground checks, and immediately before publishing.
An external rename pauses publishing until the user confirms the named
destination, even if its URI still works. Compare content hashes separately from
names; missing timestamps/capability metadata do not justify invented diagnoses.
Lost access, renames and external conflicts use a persistent yellow warning;
confirmed write/verification or private persistence failures use red. Only the
latest read-back-confirmed external revision may be described as Saved to file.

The clickable status opens an explanation and explicit confirm/reconnect,
retry, open-external-version and save-copy actions. Opening/dismissing the
popup or opening a task does not release a save barrier. Reconnection never
overwrites content that differs from the confirmed baseline; a name or shared
collection ID alone cannot identify the destination. Switching preserves each
private working copy and binding, accessible through Retained working copies.
Recovery snapshots are scoped to working path and collection identity so copies
with the same collection ID do not share a recovery destination. Restart
revalidates the binding; unpublished/restored work requires confirmation.

Advanced details supports user-initiated diagnostic JSON export with no automatic
upload. Bounded local logs record allowlisted event/error codes, versions, state,
timestamps and anonymous copy references; they omit task contents, names, paths,
full URIs and raw exceptions. Additional filenames/provider metadata require
explicit informed opt-in; full document URIs and credentials remain excluded.

Provider writes are not guaranteed atomic, and the comparison cannot prevent a
second device writing between the check and publication. Continue using one
editing device at a time. The first Android milestone reports external changes
and requires reopening when there are no pending local changes, or saving a
separate copy first when there are conflicts. Automatic provider reload is a
follow-up. A provider-confirmed save is not a guarantee of cloud synchronization.

On phones, swipe to scroll and long-press to move a placement. Keep save feedback
visible at narrow widths and accommodate the on-screen keyboard in item details.
Physical Pixel/GrapheneOS validation is required before calling Android supported.
