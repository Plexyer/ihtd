# Sorting and drag insertion

Implementation candidate, 2026-10-29. This implements step 5 / specification
item 4 in shared Rust and Flutter for Android, Windows and Linux. Physical
acceptance remains open.

## Product contract

Each view has an independent sorting choice for the collection's top level and
for each parent task/folder. Choose Manual, Title, Due date or Priority;
automatic modes support ascending/descending. Manual uses the collection's one
shared root/child order and may interleave tasks and folders. Choosing an
automatic mode does not modify that manual sequence.

Automatic modes put folders first, then tasks, sorting each group separately.
Missing dates and None priority stay last within their group in either
direction. Equal primary values use title ascending, then shared manual order
for identical titles. Title comparison uses Unicode lowercase and lexical
ordering; it does not introduce locale-specific or natural-number collation.

The top-level toolbar has a Sort control. Each row's menu has Sort children;
existing-item details also expose it. The dialog stages choices until Save
sorting; Cancel discards them. Direction is disabled for Manual. Sorting is a
separate presentation preference and does not commit an unfinished item draft.

## Dragging and shared placements

Insertion lines appear before items and at the end of sibling groups, including
nested groups. Their reserved hit areas do not change height when dragging
starts. Dropping on a card moves inside it; the top-level container target moves
to the collection's top level. Existing mouse dragging, phone long-press and
edge scrolling remain shared controls.

A between-sibling insertion uses the currently displayed order, applies the
drop, and saves the result as the shared manual order. Only the destination
parent in the current view changes to Manual; other views' automatic choices
and the source parent's choice remain unchanged. Container drops keep the
destination's active sort mode. Existing descendant-move promotion and
coalescing rules remain in force.

The owner clarified these cases on 2026-10-29:

- Hidden siblings retain their existing manual slots. Only visible siblings
  are reordered around them, including when switching from automatic sorting.
  For manual `[H, Z, Hmid, B, A]` and displayed `[A, B, Z]`, dropping Z before B
  produces `[H, A, Hmid, Z, B]`. For an incoming item, fill existing visible
  slots in the new visible order, then append the additional visible slot;
  hidden destination items retain their positions. Removing source membership
  retains the remaining source siblings' relative order.
- A child cannot be moved out of a parent appearing through multiple hierarchy
  paths, including inherited sharing. Explain that this would remove it from
  all appearances and an independent copy of the linked parent/subtree is
  needed first. Reordering within that shared parent is allowed and changes
  all its appearances. This action does not silently create a copy.

## Shared boundaries and preservation

`crates/ihtd_core/src/sorting.rs` owns sorting, validation and atomic structural
move/manual-order/mode transitions. Root order and ordered links remain the
single manual sequence. Copying a parent carries its per-view sorting choices;
deleting an item removes its obsolete sort keys without changing other scopes.

`crates/ihtd_app/src/sorting.rs` owns read-only move previews and accepted
candidates. It derives displayed siblings from the actual view/tab/expanded
projection and full occurrence paths, rather than trusting a UI-supplied order.
Plans are revision- and candidate-digest-bound and are recomputed before commit.

Shared `AppController.moveOccurrence` resolves item drafts before moving, carries
working-path/UUID identity and guards owner/view/tab inside the command queue.
Shared `ui/sort_settings.dart`, `ui/item_drag.dart` and the shell own the controls.
Sorting saves guard the original setting and owning working copy. All changes
use the existing private session and document-save coordinator; pending external
publication and recovery barriers are preserved. No platform adapter implements
an alternative sorting or dragging policy.

`View.sorting` is optional metadata: key 0 means top level, positive IDs identify
parents, and each value contains `mode` and `descending`. Absent entries mean
Manual; an empty map is omitted from serialization. Existing schema-2 files
need no conversion or rewrite on open. A frozen distributed-file preservation
test verifies unchanged bytes on open and unchanged fields/relationships after
sorting roundtrip. The schema-1 migration safety gate remains unchanged; any
future stored-data conversion still requires its own explicit safety plan.

## Verification and remaining acceptance

Host verification passed: 100 Rust tests, 187 Flutter unit/widget tests,
17 Python release/architecture checks and Flutter analysis. Native Linux
integration passed for the new sorting/drag scenario and existing desktop and
phone-layout scenarios. The new native test covers real sorting controls,
filtered insertion/end targets, shared manual order, retained automatic choices,
blocked shared-parent moves and restart behind an external rename/save barrier.
Windows and Fedora pipelines now include that scenario. The ARM64 release APK
build passed, as did native ELF LOAD and APK ZIP 16 KB alignment checks. This is
build verification, not physical Android acceptance or a published release.

- [ ] Pixel 9 Pro/GrapheneOS and Samsung: upgrade without data loss; exercise
  long-press insertion, nested end targets, scrolling, keyboard/large text and
  the linked-parent explanation using real documents.
- [ ] Native Windows and Fedora: run the integration/packaging checks and verify
  mouse insertion, scrolling, scaling, independent view choices and reopen.
- [ ] Transfer a collection across platforms; verify shared manual order,
  per-view/per-parent choices, fields, links and pending-save recovery.

These checks remain required before declaring physical acceptance complete.
