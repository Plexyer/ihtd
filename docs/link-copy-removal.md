# Linking, copying, removal and appearance counts

Implementation candidate for step 4 (specification items 3 and 13), 2026-10-29.
The [owner's later decisions](changes-2026-10-28.md#13-additional-linking-copying-and-removal-rework)
supersede the former either-Unlink-or-Delete behavior and direct-placement count.
Physical upgrade/device acceptance remains separate.

## Shared behavior

The compact Links: N counter sits below each row menu, for tasks and folders
with two or more collection appearances. It counts full root-to-item paths,
including paths inherited through linked ancestors, independent of filters,
completion tabs or expansion. For A → F → T and B → F → T, both F and T have
Links: 2. Rust computes exact decimal counts by topological propagation, without
enumerating paths or overflowing fixed-width numbers. Large counts can truncate
visually in the compact slot; the tooltip/long-press reveals the complete count.

Multiple appearances offer both Unlink and Delete. A single appearance offers
Delete only. Delete always confirms; multiple appearances explain that deletion
is global and direct users to Unlink for local removal. Delete removes all
placements of the chosen item, then only children with no surviving root/parent
placement. Shared children elsewhere survive, together with their branches.
Deleted IDs remain reserved; affected container rules keep the existing yellow
view warning and repair workflow.

Unlink removes the selected occurrence immediately when that relationship is
not shared through an ancestor. The clicked hierarchy path is carried into
item details. Details show the current place, parent navigation and the same
actions as the row menu. A removed/stale selected path is cleared; a remaining
item can be navigated at its surviving canonical occurrence. Programmatically
opened details use a canonical occurrence and show that place explicitly.

### Child Unlink blocked by linked ancestry

A child of a linked parent cannot be removed from only one parent appearance
by changing the parent's shared child list. The confirmation names the blocking
parent and offers Cancel or Copy parent and remove child. Acceptance:

1. Finds the earliest shared ancestor on the selected path. This avoids replacing
   a deeper edge that would itself affect several ancestor appearances.
2. Creates a full-depth independent copy of that parent and every child appearance,
   including separate copies of repeated linked items.
3. Replaces only the selected parent occurrence, in the same sibling/root position.
4. Removes the selected copied child and its copied descendants. No copied removed
   branch is promoted to top level; original items and other paths remain intact.

The entire replacement/pruning is one validated atomic mutation. Cancellation,
stale approval or failure changes nothing and consumes no IDs in the document.

## Link / copy task to

The action now treats the clicked task/folder as the source and searches for a
destination task/folder or Top level. Duplicate titles retain their IDs/kinds in
the search list. The popup contains:

- Link/Copy mode, default Link.
- Copy depth, disabled for Link. Copy defaults to Source item only; original
  children stay linked. Available child depths and All descendants are offered.
- Make every appearance independent, unchecked by default. Default copying
  creates one new item per unique source item and preserves its internal links.
  Checking it makes each copied appearance a distinct new item.
- Cancel and one mode-dependent Link to or Copy to action.
- An info button revealing two short explanations of linking versus copying.

Link excludes the source and every descendant. It adds a placement and preserves
existing placements, including an existing root occurrence. Duplicate destinations
fail without mutation. Copy allows self/descendant destinations only at full depth;
selection forces and locks All descendants with a visible explanation. Switching
back to Link clears a now-invalid destination.

Copy always uses a finite pre-operation snapshot; it never traverses the newly
attached copy. A default partial copy assigns fresh IDs to all unique items
reachable within the depth. References from copied parents reuse an already
created copy even when that occurrence is deeper than the limit. Uncopied boundary
parents retain their original children: copying never rewrites an original subtree
to manufacture references to copied items. Independent partial copies still link
original children beyond the boundary.

Copies retain item fields, tags, local completion settings, shared indicator
preferences and per-view container preferences. Derived completion is recomputed
under the destination's normal rules. Global views/rules are not duplicated or
retargeted. New-child folder reappearance and automatic ancestor completion follow
existing shared model policy. Copied tag assignments create no manual popularity
history; the later popularity implementation must preserve that distinction.

Independent expansion of a highly shared DAG can be enormous. Operations creating
more than 100,000 copied items fail with a smaller-depth/preserve-links suggestion;
the original document remains unchanged. Normal operations are iterative rather
than recursive.

## Implementation and compatibility

`crates/ihtd_core/src/hierarchy.rs` owns counts, copy options, cloning and explicit
action previews/execution. JSON commands expose read-only copy_options and
preview_item_action, then revision-checked link_or_copy / apply_item_action.
An action preview binds the full path, explicit action, document/revision,
blocking parent and deletion consequences. Changed/tampered approvals fail.

Flutter uses shared `ui/link_copy.dart`, `ui/item_removal.dart` and controller
resolution/working-copy guards. Finish unfinished item edits first; Keep editing
aborts. Read-only previews do not publish or claim saving. Mutations use the
existing private session and DocumentSaveCoordinator; connection/conflict/recovery
barriers remain intact. A failed/repeated copy cannot reuse its stale revision to
create another accepted copy. The former preview_removal/remove_placement helpers
remain for legacy compatibility tests; new product callers must use explicit
appearance-aware actions, never those historical either/or helpers.

No stored-data migration is needed: counts and path context are derived, and
copy/delete/unlink are explicit user operations on the unchanged schema-2 graph.
Opening existing collections performs no graph conversion or rewrite. Existing
schema-1 files still require the verified-backup migration gate. Copies use fresh
IDs and preserve deleted-ID reservations; no draft-store conversion is introduced.

## Verification and physical acceptance

Automated coverage includes exact large counts, depth-boundary reuse, independent
copies, finite self-copy, cycle/stale rejection, global cascade retention, linked
ancestor replacement, row/detail actions, confirmation cancellation, draft guards,
search/mode/depth controls and document-owner checks. Native
integration_test/hierarchy_actions_test.dart uses real Rust/Flutter files to verify
blocked-Unlink confirmation and isolation, partial-copy reuse, deleted-container
warnings, external rename barriers and restart. Windows/Fedora pipelines include it.

Before release, test on Pixel/GrapheneOS, Samsung, Windows and Fedora:

1. Upgrade/open a real existing collection; verify unchanged items, links, settings,
   views and drafts, and no file rewrite merely from opening.
2. Link a folder twice. Check parent/child Links counters across tabs and filters.
   Verify both actions, global Delete's explanation, cancellation and shared-child
   preservation. Repair a view referring to a deleted container.
3. Unlink a child beneath linked and nested linked parents. Cancel first, then
   accept replacement; verify only the selected path is independent/changed, with
   no removed copied branch at top level and no changes to originals elsewhere.
4. Exercise source-only, intermediate and full copy depth, both repeated-item
   choices, and copy into self/descendants. Edit originals and copies to verify
   exactly the intended sharing. Check saved preferences and completion behavior.
5. Use search, duplicate titles, Top level, info expansion, large text, short
   windows and the phone keyboard. Actions and selected destinations stay usable.
6. Resolve dirty drafts before actions. Change the graph or working collection
   while a popup is open; reject stale actions. Rename/revoke the external file,
   perform an accepted action locally, restart and recover without false Saved
   feedback or bypassing reconnection safeguards.

No app version bump or production release is part of this task. Host checks do
not establish native phone keyboard, upgrade or provider acceptance.

Cloud verification, 2026-10-29: static analysis, 182 Flutter tests, 90 Rust tests
and 17 Python checks passed. Real Rust/Flutter hierarchy-action, existing desktop
and phone-layout integrations passed on the Linux host. The phone test now awaits
asynchronous Save/editor closure before asserting a swipe changes no revision.
An ARM64 release APK built successfully; all four native libraries passed 16 KB
ELF alignment and the APK passed ZIP alignment. Windows/Fedora native CI and
physical acceptance remain separate checks.
