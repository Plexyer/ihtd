# IHTD prototype behavior

Updated 2026-10-28. This records the implemented prototype and the user's
clarifications; platform validation is listed separately in README.md.

## Approved changes awaiting implementation

The [2026-10-28 Changes.docx specification](docs/changes-2026-10-28.md) and
[checklist backlog](docs/FEATURE_CHECKLIST.md#owner-clarified-changesdocx-backlog)
record the owner's later approved changes, including cancellable item drafts,
appearance counts, global Delete/blocked child Unlink, configurable Link/Copy,
sorting, indicators and tag suggestions. Implemented candidates and remaining
acceptance are identified below and in the checklist; other backlog items remain
pending. The sections below also describe the existing prototype;
use the later specification when implementing the approved changes rather
than treating the old removal/autosave behavior as the new target.

The owner also requires a [migration safety gate](docs/changes-2026-10-28.md#14-migration-safety-prerequisite):
where migration is necessary, first create and verify a backup beside the original
collection or in an authorized backup folder. Stop if backup fails; migrate a
separate candidate and validate it before guarded publication. Preserve recovery
data and automatically persist exportable, redacted failure diagnostics. This is
implemented as a shared migration-safety candidate; see
[behavior and acceptance](docs/migration-safety.md). Current schema-2 files need no
conversion. Physical upgrade acceptance remains required, and later feature/data
migrations need their own explicit plans and preservation tests.

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

## Removing tasks and folders

Owner confirmed 2026-10-14. Count actual incoming parent links plus one
existing root placement, including explicit shared roots. Multiple filtered
views or paths through shared ancestors do not count as additional placements.

With two or more placements, show **Unlink** and immediately remove only the
selected root or parent-child relationship without confirmation. Preserve the
item, its attributes, children and other placements. With exactly one placement,
show **Delete** and require confirmation describing the affected items. Delete
the item and recursively delete descendants with no surviving placement;
preserve descendants linked outside the removed branch or at the top level,
and their surviving children. Do not promote children or add Undo/trash.

Linked tasks/folders have the same children everywhere. Removing a child from
a shared parent affects every appearance of that relationship. Execute removal
atomically, reject stale confirmations, preserve surviving IDs and order, and
use the existing shared saving/recovery flow on all platforms.

A saved view referring to a deleted task/folder keeps its rule and its Boolean
scope. That container rule matches nothing. Affected views receive a yellow
shade and a short warning above the hierarchy identifying the rule position
and deleted container ID; tapping it opens the rule editor. The editor shows
“Deleted container” and allows replacing/removing the rule. Repair clears the
warning. Only deleted IDs are retained as metadata, not item names or contents;
existing schema-1/2 files default this optional metadata to an empty set.

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

Shared editor design, owner approved and implemented 2026-10-14:
conditions use infix AND/OR connectors, circular plus buttons for empty slots
and scoped chain-end addition, and parentheses for mixed logical groups.
Narrow screens put the connector at the start of the following operand row
(Option A); wider screens use inline space when available. Same-operator
AND/AND and OR/OR nesting appears as one chain. Exactly-one/XOR and NOT retain
their boundaries. Existing matching, task-creation defaults and saved views
remain compatible. The editor uses isolated drafts and focused condition forms;
empty slots are never stored as All items. Changing a connector retains its
operands. Same-operator flattening is a display projection, preserving stored
branch boundaries and creation hints on unchanged/name-only saves. Stale view
edits and different working copies (including copies sharing a UUID) are rejected
inside the command queue. Only outer Save view commits the expression; tag
creation remains a separate collection operation. Physical acceptance is pending.
See [implementation plan](docs/view-expression-editor-plan.md) and
[acceptance guide](docs/view-expression-editor-acceptance.md).

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

## Item editor drafts (implementation candidate)

Follow [the approved draft/Save/Cancel behavior](docs/item-editor-drafts.md).
Tasks/folders stage editable fields privately until Save; Cancel discards them.
Back/Escape and explicit switching with edits prompt Save/Discard/Keep editing;
existing-editor outside clicks save only if valid, and new-item outside clicks
prompt Create/Discard/Keep editing. Saving closes the whole editor. Backgrounding
and private checkpoints do not commit drafts. Visibility and collection-tag
creation remain immediate separate operations. Unfinished drafts can be restored
or discarded after restart and stay bound to their working copy, even for
collections sharing a UUID. Physical acceptance remains open.

## Collection settings (implementation candidate)

Follow [collection settings and inheritance](docs/collection-settings.md).
Settings belong to the collection: suggested unselected tags defaults to 5 and
usage half-life to 3 days, with collection defaults for summary indicators.
Optional parent defaults and parent/view overrides inherit independently for
each indicator; resetting one field resumes inheritance. Settings forms stage
choices until Save, reject stale or different-copy saves and preserve external
publication barriers. Separate indicator preferences do not commit item drafts.
Optional schema-2 metadata preserves existing data without conversion or a
rewrite on open. Actual summary metrics and tag suggestions remain later tasks;
physical upgrade/device acceptance is pending.

## Fields and files

Title, tags, plain-text notes, date-only due date, and priorities None / Low /
Medium / High. No custom fields.

One independent .ihtd file is open at a time. Native filesystem open/save
dialogs support local, removable, and mounted paths. Accepted mutations save
automatically after acceptance. Item typing is privately checkpointed until the
user commits the cancellable draft. External revisions are reported
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
toolchain. Every packaged native ELF library must have at least 16 KB LOAD
alignment, independently of APK ZIP alignment; enforce both before distribution. Confirm the installed Android version during physical phone testing.
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

## Shared responsive editors and surfaces

Task/folder creation and view editing use one responsive Flutter dialog layout
on Android, Windows and Linux. Forms scroll with inner paint space for floating
labels and rule outlines. Normal layouts keep actions outside the form scroll;
short windows or large text include the title and actions in the scroll so they
remain reachable. Keyboard insets are applied once by Dialog, and partial rows
during scrolling can be brought fully into view at either scroll limit.

Header, canvas and sidebar are shared theme surface roles. The top safe inset
continues the header, the lower safe inset continues the canvas, and the full
drawer (including its inset margins) uses the sidebar surface without a default
surface tint. Transparent system bars use contrasting icons for their adjacent
surfaces; Android window themes prevent extra system contrast strips and use
the current light palette even when the OS uses dark mode. Keyboard-owned bars
remain controlled by the keyboard. A full app dark theme is a separate feature.

## Updates (implementation candidate, physical acceptance pending)

Owner approved 2026-10-15. Implement one shared release-discovery/coordinator/UI
flow for Android, Windows and Fedora; native adapters supply OS capabilities.
The drawer button sits beside the current view name. A newer compatible stable
GitHub Release shows a blue download arrow/circle in the header; its popup shows
version, notes and size. Download confirmation closes the popup, then animated
progress runs while editing continues. Only a verified download becomes a green
tick. Android tapping that tick flushes drafts/checkpoints locally and opens the
system installer without an additional app confirmation. Android controls final
approval/reopening. Persist/reconcile actual installed version and hide the icon
when current. No silent installs, uninstalls or user-data cleanup.

Android downloads continue through DownloadManager while minimized/locked; use
native source permission when needed, app-scoped storage and pinned cryptographic
APK signature plus package/version/size/hash checks. No Play dependency. Updates
need Internet permission; offline core editing remains available. Automatic checks
are at most daily, optional, and anonymous; manual checks explain failures.
Public stable complete releases only, never draft/prerelease artifacts or mere
master merges. Desktop unsigned packages use manual release-page guidance until
trusted package signing is available. Public visibility requires the history/
asset audit and owner review. Public visibility and corrected protections are
verified; original source uses AGPL-3.0-only following the owner's confirmation. See
[update acceptance and limitations](docs/update-acceptance.md).
