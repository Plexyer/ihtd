# Placement-aware Unlink/Delete implementation plan

Created 2026-10-14. Planning only: no runtime changes. Based on merged
`development`. Read `AGENTS.md`, `REQUIREMENTS.md`, shared architecture and the
feature checklist before implementing. Implement once for Android, Windows
and Linux. Owner decisions below were confirmed on 2026-10-14 and are
recorded in requirements. This plan is ready for implementation.

## Confirmed product decisions

1. Delete recursively removes children that have no remaining placement after
   removal. Preserve children linked elsewhere, including explicit root
   placements, and preserve their surviving branches. Do not promote children.
2. Confirm Delete, explaining which items will be deleted and which shared
   children will survive. Unlink applies immediately without confirmation.
   Undo and trash are outside this task.
3. Linked folders share the same children everywhere. Removing a child from
   that folder affects every appearance of that relationship. Multiple paths
   through a shared folder are not separate placements of its child.

## Agreed behavior

- Tasks and folders follow the same rules. Two or more actual placements means
  **Unlink**; exactly one means **Delete**.
- Count distinct incoming parent links plus one effective top-level placement,
  including explicit shared roots. Filtered views, expanded paths and multiple
  appearances through a shared ancestor do not create placements.
- Unlink removes only the selected root or parent-child relationship. Keep
  item identity, attributes, children, remaining links and their ordering.
- Delete removes the item itself at its last placement. Never silently delete
  descendants still retained elsewhere. Apply the confirmed recursive policy.
- Keep existing save barriers, pending recovery and publication verification.
  Removing an item must never delete a collection or recovery file.

## 1. Establish baseline and finalize semantics

- [ ] Pull latest development; preserve existing work; create a task branch.
- [x] Record the three owner answers here and in requirements/checklist.
- [ ] Build fixtures: sole root, sole nested item, two parents, explicit root
  plus parent, shared ancestor paths, filtered context rows and shared descendants.
- [ ] Inspect `Document::roots`, `root_order`, `links`, `transact`, completion,
  view preferences and storage validation before selecting the mutation API.

## 2. Add one authoritative domain operation

- [ ] In `crates/ihtd_core/src/model.rs`, introduce placement identity
  (item ID plus optional immediate parent), authoritative placement count and
  a removal preview: action, removed IDs, affected placements and preserved
  children. Validate that the requested placement still exists.
- [ ] Execute removal atomically with `Document::transact`; reject stale
  previews/revisions. Never silently turn an approved Unlink into Delete when
  links change while a dialog is open. Re-preview and request any newly needed
  confirmation. Invalid requests leave document and revision unchanged.
- [ ] Handle roots explicitly: removing a shared root must retain parent links;
  last-placement deletion must remove the item so implicit-root fallback cannot
  resurrect it. Existing low-level unlink keeps items and is insufficient.
- [ ] Implement the approved child policy. For recursive deletion, determine
  which nodes lose every surviving incoming/root placement; retain a shared
  branch and its children, including descendants with parents inside another
  retained branch. Use iterative graph traversal, not recursion/depth limits.
- [ ] Remove links, root entries and per-view preferences for deleted IDs;
  keep unrelated tags/views and stable surviving IDs, never reuse deleted IDs.
  Recompute completion/inheritance and validate graph/document invariants.

## 3. Expose commands and retain persistence guarantees

- [ ] Add preview/execute commands in `crates/ihtd_app/src/lib.rs` and shared
  presentation metadata in `presentation.rs` where appropriate. Reuse the
  existing JSON bridge; regenerate bindings only if bridge signatures change.
- [ ] Route through `app/lib/services/app_controller.dart` and existing private
  working-copy/save-coordinator flow. No platform-specific deletion policy.
- [ ] Audit existing `unlink` callers; replace user-facing removals with the
  authoritative action. Preserve internal link manipulation used for moves.
- [ ] Verify schema-2 round trips and schema-1 migration remain compatible.
  Reopening must not recreate deleted items or lose preserved shared branches.

## 4. Shared Flutter interaction

- [ ] Add dynamic Unlink/Delete to each row menu in `app_shell.dart`, carrying
  its actual immediate parent/root identity from the row path, not title or
  selected item ID alone. Support tasks, folders and filtered context rows.
- [ ] Replace the details-panel 'Remove this placement; keep item' action in
  `item_editor.dart`. Show explicit shared root placements as well as parents.
  Where no placement context is known, offer a placement choice rather than
  guessing or introducing an unapproved Delete everywhere command.
- [ ] Implement Delete confirmation and immediate Unlink. Delete messaging must
  explain child effects and preserved shared items using preview results;
  make destructive actions distinguishable and cancel leave everything intact.
- [ ] Refresh labels after mutations. Clear selection only for a deleted item;
  preserve surviving selection, repair stale expanded paths and refresh views.
- [ ] Show normal pending/saved/recovery feedback through the shared coordinator.
  Verify dialog reachability with keyboard, narrow screens and large text.

## 5. Meaningful automated verification

- [ ] Rust: root/nested tasks and folders; two parents; root+parent; last-root
  deletion; same child through shared ancestor paths; approved child policy;
  diamonds/shared descendants, deep graph, completion changes and stable order.
- [ ] Rust: stale previews/missing placement/cancel produce no mutation;
  atomic rollback, no dangling preferences/links and no ID reuse.
- [ ] Storage/application: save/reopen/export/import compatibility, revisions,
  migration and surviving shared attributes/subtrees.
- [ ] Flutter: row/details labels count actual placements independently of
  views, correct selected relationship, confirmation/cancel, stale-state refresh,
  selection cleanup, small/large-text layout and coordinator pending recovery.
- [ ] Integration: real Rust-backed remove/shared preservation and reopen;
  regression coverage for drag descendant moves and existing link creation.
- [ ] Run workspace Rust tests, relevant Flutter tests/analyze and shared
  integration checks. Native checks follow repository triggers; do not treat
  build success as physical acceptance.

## 6. Documentation, review and physical acceptance

- [ ] Update requirements/checklist, architecture only if boundaries change,
  and a short acceptance guide. Record implemented versus untested behavior.
- [ ] Verify on Pixel/GrapheneOS and desktop: task/folder, root/nested/shared,
  filter views, cancel and child policy. Test disconnected external file:
  removal remains safely pending locally and reconnect publishes the correct
  result without deleting other collections or recovery copies.
- [ ] Commit, push and open PR into development with semantic examples and
  validation evidence. Leave merge and stable release to the owner.

Completion requires owner-approved semantics, shared implementation, passing
tests and accurate physical acceptance status. General Undo, trash, Delete
everywhere and per-path children are outside scope unless explicitly approved.
