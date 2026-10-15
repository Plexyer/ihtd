# Placement-aware Unlink/Delete implementation plan

Created 2026-10-14. Shared implementation and automated/native verification are complete; physical acceptance remains pending. Based on merged
`development`. Read `AGENTS.md`, `REQUIREMENTS.md`, shared architecture and the
feature checklist before implementing. Implement once for Android, Windows
and Linux. Owner decisions below were confirmed on 2026-10-14 and are
recorded in requirements. Physical acceptance remains a separate owner check.

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
4. Preserve views referencing deleted containers. The affected view gets a
   yellow shade and a minor warning above its hierarchy identifying the rule
   to review. The editor shows Deleted container; replacement/removal clears
   the warning. Keep Boolean scope; only that container predicate matches nothing.

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

- [x] Pull latest development; preserve existing work; use the plan task branch.
- [x] Record the three owner answers here and in requirements/checklist.
- [x] Build fixtures: sole root, sole nested item, two parents, explicit root
  plus parent, shared ancestor paths, filtered context rows and shared descendants.
- [x] Inspect `Document::roots`, `root_order`, `links`, `transact`, completion,
  view preferences and storage validation before selecting the mutation API.

## 2. Add one authoritative domain operation

- [x] In `crates/ihtd_core/src/removal.rs`, introduce placement identity
  (item ID plus optional immediate parent), authoritative placement count and
  a removal preview: action, removed IDs, affected placements and preserved
  children. Validate that the requested placement still exists.
- [x] Execute removal atomically with `Document::transact`; reject stale
  previews/revisions. Never silently turn an approved Unlink into Delete when
  links change while a dialog is open. Re-preview and request any newly needed
  confirmation on a fresh attempt. Invalid requests leave document and revision unchanged.
- [x] Handle roots explicitly: removing a shared root must retain parent links;
  last-placement deletion must remove the item so implicit-root fallback cannot
  resurrect it. Existing low-level unlink keeps items and is insufficient.
- [x] Implement the approved child policy. For recursive deletion, determine
  which nodes lose every surviving incoming/root placement; retain a shared
  branch and its children, including descendants with parents inside another
  retained branch. Use iterative graph traversal, not recursion/depth limits.
- [x] Remove links, root entries and per-view preferences for deleted IDs;
  keep unrelated tags/views and stable surviving IDs, never reuse deleted IDs.
  Recompute completion/inheritance and validate graph/document invariants.

## 3. Expose commands and retain persistence guarantees

- [x] Add preview/execute commands in `crates/ihtd_app/src/lib.rs` and shared
  presentation metadata in `presentation.rs` where appropriate. Reuse the
  existing JSON bridge; regenerate bindings only if bridge signatures change.
- [x] Route through `app/lib/services/app_controller.dart` and existing private
  working-copy/save-coordinator flow. No platform-specific deletion policy.
- [x] Audit existing `unlink` callers; replace user-facing removals with the
  authoritative action. Preserve internal link manipulation used for moves.
- [x] Verify schema-2 round trips and schema-1 migration remain compatible.
  Reopening must not recreate deleted items or lose preserved shared branches.

## 4. Shared Flutter interaction

- [x] Add dynamic Unlink/Delete to each row menu in `app_shell.dart`, carrying
  its actual immediate parent/root identity from the row path, not title or
  selected item ID alone. Support tasks, folders and filtered context rows.
- [x] Replace the details-panel 'Remove this placement; keep item' action in
  `item_editor.dart`. Show explicit shared root placements as well as parents.
  Where no placement context is known, offer a placement choice rather than
  guessing or introducing an unapproved Delete everywhere command.
- [x] Implement Delete confirmation and immediate Unlink. Delete messaging must
  explain child effects and preserved shared items using preview results;
  make destructive actions distinguishable and cancel leave everything intact.
- [x] Refresh labels after mutations. Clear selection only for a deleted item;
  preserve surviving selection, repair stale expanded paths and refresh views.
- [x] Show normal pending/saved/recovery feedback through the shared coordinator.
  Verify dialog reachability with keyboard, narrow screens and large text.

## 5. Meaningful automated verification

- [x] Rust: root/nested tasks and folders; two parents; root+parent; last-root
  deletion; same child through shared ancestor paths; approved child policy;
  diamonds/shared descendants, deep graph, completion changes and stable order.
- [x] Rust: stale previews/missing placement/cancel produce no mutation;
  atomic rollback, no dangling preferences/links and no ID reuse.
- [x] Storage/application: save/reopen/export/import compatibility, revisions,
  migration and surviving shared attributes/subtrees.
- [x] Flutter: row/details labels count actual placements independently of
  views, correct selected relationship, confirmation/cancel, stale-state refresh,
  selection cleanup, small/large-text layout and coordinator pending recovery.
- [x] Integration: real Rust-backed remove/shared preservation and reopen;
  regression coverage for drag descendant moves and existing link creation.
- [x] Run workspace Rust tests, relevant Flutter tests/analyze and shared
  integration checks. Native checks follow repository triggers; do not treat
  build success as physical acceptance.

## 6. Documentation, review and physical acceptance

- [x] Update requirements/checklist, architecture only if boundaries change,
  and a short acceptance guide. Record implemented versus untested behavior.
- [ ] Verify on Pixel/GrapheneOS and desktop: task/folder, root/nested/shared,
  filter views, cancel and child policy. Test disconnected external file:
  removal remains safely pending locally and reconnect publishes the correct
  result without deleting other collections or recovery copies.
- [x] Commit, push and open PR into development with semantic examples and
  validation evidence. Leave merge and stable release to the owner.

Completion requires owner-approved semantics, shared implementation, passing
tests and accurate physical acceptance status. General Undo, trash, Delete
everywhere and per-path children are outside scope unless explicitly approved.

## Verification evidence

- Final runtime commit: `89d6e0e` (base feature commit `6e06079`); PR #16 targets development.
- 67 workspace Rust tests and 75 Flutter tests passed, including 11 removal tests.
- Shared library, tests and integration sources analyze cleanly; 13 Python
  release/architecture tests passed. GitHub Development checks passed in run
  `38568092620`.
- Real Linux integration passed: UI consent/cancel/cascade, retained shared roots,
  view-rule warning/repair, save/reopen and deletion while an external file was
  renamed. Reconnect publishes the retained result; a fresh startup opens it.
- The startup assertion now waits for initialization and renders its final frame,
  avoiding a race between native file IO and the first UI settle.
- Physical acceptance and stable publication remain pending. Follow
  [the acceptance guide](unlink-delete-acceptance.md). Windows/Fedora package
  rebuilds remain part of the master/release workflow; adapters did not change.

- The existing narrow-screen integration also passed, including touch scrolling,
  keyboard/editor flushing and descendant drag-and-drop regression.
- Signed ARM64 Android candidate: `IHTD-0.2.2-build10-android-arm64-final-test.apk`,
  built from the runtime source above. App ID `dev.ihtd.app`, API 35 minimum / 36
  target, code 10, version 0.2.2. Permanent certificate matches the pin; ZIP and
  all ELF LOAD alignments meet 16 KB. No internet/broad-storage permission.
  SHA-256: `4ac47b14b689c2226ccd4487aebf7079371b5a3c7f9dcde8e4c2df1ee4d12fcf`.
  Binary and SHA256SUMS are local ignored outputs under `dist/unlink-delete/`,
  not committed or published as a stable GitHub release.
- Run desktop integration and APK builds sequentially: Flutter regenerates
  plugin registration across targets, and concurrent runs can leave test-only
  registration in the release build. The final APK was rebuilt sequentially
  using the supported dependency refresh and then independently verified.

- The deleted-container message is restricted to recorded deleted IDs; an
  empty/new container choice is not mislabelled as deleted. The extended view
  warning regression passed, and the final signed APK includes this guard.
