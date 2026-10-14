# Infix view-rule editor implementation plan

Created 2026-10-14. Shared implementation and automated verification complete;
physical acceptance remains pending. This is
the handoff for the next implementation session, based on `development` at
`9fa4ee2` (merged Unlink/Delete PR #16). Complete the steps in order and record
verification evidence here. Physical tests use the linked acceptance guide.

## 1. Read the baseline and preserve ownership

- [x] Read `AGENTS.md`, `REQUIREMENTS.md`, `docs/FEATURE_CHECKLIST.md`,
  `docs/shared-app-architecture.md`, `docs/building.md` and this plan.
- [x] Inspect status/upstream, pull with `--ff-only`, and preserve all existing
  work. Continue on the plan branch after it is synchronized, or create a new
  `codex/` branch from current development if the plan has already been merged.
- [x] Inspect the current rule form and its tests before replacing it. Record
  the baseline checks and existing saved-view fixtures.

Implement one editor in shared Flutter for Android, Windows and Fedora/Linux.
Rust remains authoritative for filter evaluation, validation, creation defaults
and storage. Adapt to width, height, text scale, keyboard and input capabilities;
do not introduce OS-name branches or change native document adapters.

Relevant current files:

| Concern | Location |
| --- | --- |
| View draft, save/delete view, existing rule fields | `app/lib/ui/view_editor.dart` |
| Safe scrolling, keyboard constraints, action layout | `app/lib/ui/editor_dialog.dart` |
| Shared controller, dispatch, selected view and issue metadata | `app/lib/services/app_controller.dart` |
| Filter AST, matching, validation, creation hints and issue paths | `crates/ihtd_core/src/filter.rs` |
| Add/edit view commands, snapshots | `crates/ihtd_app/src/lib.rs` |
| Outline with matching versus context-only rows | `crates/ihtd_app/src/presentation.rs` |
| Deleted-view warnings and opening the editor | `app/lib/ui/app_shell.dart` |
| Existing rule/dialog/removal regressions | `app/test/layout_polish_test.dart`, `app/test/item_removal_test.dart` |
| Real shared backend and narrow-layout integration | `app/integration_test/app_test.dart`, `app/integration_test/phone_layout_test.dart` |

Suggested new shared files, adjust names to existing conventions:
`app/lib/ui/rule_expression.dart` for rendering, `rule_condition_editor.dart`
for focused condition forms, and `app/lib/services/rule_draft.dart` for draft
operations and the display projection (these locations are now implemented). Keep reusable transformation helpers
separate from widgets. The native bridge signatures need not change for this UI
task; regenerate bindings only if an actual API change requires it.

## 2. Implement the confirmed interaction contract

- [x] Replace the logical-heading/wrapping-card presentation with an infix
  expression: conditions separated by AND/OR, with parentheses for mixed logic.
  Do not retain the old group-heading layout as the primary editing interface.
- [x] Use compact readable condition summaries; selecting a condition opens
  its focused controls. Selecting a connector exposes the chain's operator
  choices and explains that changing it affects that whole chain.
- [x] Selecting AND as a starting expression provides two empty circular plus
  slots, `(+) AND (+)`; OR behaves equivalently. Offer a single condition and
  explicit All items as valid starting choices too.
- [x] An empty slot's plus opens the condition/group picker. Offer every
  existing leaf kind plus AND, OR, Exactly one and NOT. Mixed operators create
  an explicit parenthesized group, never an implicit precedence-dependent mix.
- [x] Add one circular plus at the end of each chain. Inner plus belongs before
  the closing parenthesis; outer plus belongs after it. Adding through that
  button inserts the chain's connector automatically and preserves other nodes.
- [x] Same-operator AND/AND and OR/OR chains display as one continuous chain.
  Different operators retain parentheses. Preserve exactly-one/XOR and NOT
  boundaries; those nested expressions cannot be flattened by this rule.
- [x] On narrow layouts use owner-selected **Option A**: the connector starts
  the following condition/group row, not a separate separator row or a heading
  above everything. Indent grouped operands modestly and align parentheses.
- [x] On wider layouts show expressions inline where they fit, wrapping at
  expression boundaries. Maintain a connector's association with its operand.
- [x] Give every plus a precise tooltip/accessibility name: Add condition to
  AND chain, Add condition to OR chain, or Fill empty condition. Its picker also
  identifies the active scope, so adjacent inner/outer pluses are distinguishable.

Owner-approved examples (`+` represents a circular plus button):

```text
Initial: (+) AND (+)
After selecting Title and an OR group:
  Title contains "xx" AND ((+) OR (+))
Filled:
  Title contains "xx" AND (Due before X OR Due after Y +) +
Outer plus adds Priority:
  Title contains "xx" AND (Due before X OR Due after Y +) AND Priority is High +
Inner plus adds Tag:
  Title contains "xx" AND (Due before X OR Due after Y OR Tag is Packing +) +

Narrow layout:
Title contains "xx"
AND (
    Due date before X
    OR Due date after Y
    + Add OR condition
)
AND Priority is High
+ Add AND condition
```

The essential addition path is the scoped chain-end plus. Insertion between
existing operands can use a condition menu; do not clutter every filled gap
with another plus. A contextual Combine with another condition action wraps
the selected operand, for example `A AND B` becomes `A AND (B OR (+))`.
These are implementation defaults consistent with the agreed design, not
additional confirmed owner preferences. Resolve routine details in this scope;
ask only if a proposed change alters product semantics.

## 3. Model draft editing without changing filter behavior

- [x] Keep an isolated editor draft cloned from the saved filter. Use stable
  UI node/slot identities independent of list positions and document item IDs.
  Do not serialize these UI identities into `.ihtd` files.
- [x] Represent unfilled slots as draft-only nodes, not `{"op":"all"}`.
  Otherwise an unfinished OR branch would match everything. Block saving an
  unfinished draft and identify the slot needing attention.
- [x] Provide draft operations: fill slot, append to a specified chain, edit
  leaf, change chain connector while retaining operands, wrap selected operand,
  remove operand/group, and map displayed nodes back to the underlying AST.
- [x] After removing one of two AND/OR operands, show the remaining expression
  naturally; do not unexpectedly replace it with All items. Removing the last
  draft operand leaves a visible empty slot until filled or explicitly replaced
  with All items. Preserve loaded valid empty/single-child groups on unchanged
  save; their existing semantics are not new empty draft placeholders.
- [x] Do not flatten XOR, distribute AND over OR, deduplicate operands, or
  simplify NOT. Duplicate alternatives affect exactly-one matching, and broad
  algebraic rewrites can alter task-creation hints.
- [x] Preserve order, actual tag/container IDs, date values, text comparison,
  case sensitivity, recursive membership, saved-view preferences and view ID.
  Do not guess reference identity from display names; duplicate names are valid.

**Important compatibility constraint:** matching equivalence alone is not enough.
`FilterExpr::creation_defaults` treats simple tag OR/XOR specially (all tags for
simple OR; lowest viable ID for simple XOR), and distinguishes other nested
alternatives. Flattening a stored OR can change creation suggestions even though
the same items match. Existing deleted-container warnings also use AST paths.

Prefer a flattened **display projection** that retains the original tree and
stable source-node mapping. Opening, cancelling, or saving only a renamed view
must preserve its original filter and creation behavior. Apply structural edits
only to the relevant draft subtree. Avoid a global load/save normalization pass.
If persisted normalization is needed, first demonstrate matching AND creation
defaults/requirements compatibility, with tests, and preserve issue mapping.
Do not silently change existing hint policy to accommodate the new layout.

## 4. Build reusable summaries, pickers and focused forms

- [x] Render a summary for every existing rule kind. Show critical options
  (case sensitivity, descendant scope, negation) visibly, not only in the editor.
- [x] Reuse validated controls for each leaf form:

| Condition | Required controls |
| --- | --- |
| Title / Notes | Field, all six existing comparisons, text, case sensitivity |
| Tag | Search/select by actual ID; create-tag entry in this picker |
| Inside folder/task | Container picker accepting both kinds; direct versus all descendants |
| Due date | All five date comparisons with date picker |
| Date presence | Has date / No date, with no unused date value |
| Priority | Is / At least / At most; None / Low / Medium / High |
| Item type | Task / Folder |
| Completion | Unfinished / Completed |
| All items | Explicit constant-true expression, distinct from an empty draft slot |
| AND / OR | Infix chain with scoped addition and editable connector |
| Exactly one | Clearly labelled infix connector/group; exactly one matching branch, not parity XOR |
| NOT | Visible NOT operand/group; scope always explicit |

- [x] Preserve stored unknown/deleted-reference diagnostics. Deleted containers
  must remain visible as Deleted container (#ID), with yellow repair messaging
  and Replace/Remove actions; never select a different live container implicitly.
- [x] Separate condition-form Done/Cancel from outer Save view/Cancel. Form
  cancellation discards that form's changes; outer cancellation discards the
  expression draft. Text focus/selection survives responsive relayout.
- [x] Keep tag creation's existing collection-level semantics explicit: creating
  a tag is a separate operation, not a promise that cancelling the view rolls
  back tag creation. Any change to that behavior needs a separate decision.
- [x] Keep Save/Cancel reachable and distinct from Delete view; move the
  destructive view action into a separate secondary menu/action area. Preserve
  its confirmation and the last-view protection.

## 5. Responsive expression layout and accessibility

- [x] Build the narrow Option-A renderer first, then extend it to inline desktop
  presentation using one draft/controller and the same editing widgets.
- [x] Reuse `EditorDialog`'s scrolling, floating-label paint space and keyboard
  constraints. An adaptive larger editor surface is acceptable when needed;
  avoid platform-specific dialogs and nested scroll areas competing for gestures.
- [x] Wrap long conditions readably; keep full names/values available. Do not
  make ellipsis the only way to display a rule's meaning or require horizontal
  scrolling to reach operands/addition buttons.
- [x] Bound indentation in deep mixed groups. If drilling into a group becomes
  necessary, show its expression path and preserve parent scope/draft identity;
  do not impose a new nesting limit or hide active logic without an indication.
- [x] Respect large text and short/landscape/keyboard-reduced height; narrow
  desktop windows follow the same rules as narrow phones.
- [x] Circular plus icons need touch-sized targets, keyboard activation,
  visible focus and accessible scope labels. Operators, parentheses and warning
  state must be understandable without color alone. Add keyboard-accessible
  menus for edit/remove/combine; drag-and-drop is not required for this task.

## 6. Integrate saving and rule-issue repair

- [x] Replace `_RuleEditor` in the new/edit view flow with the shared expression
  editor. Keep add/edit view dispatch, backend validation and controller
  selection behavior through the existing working-copy/save-coordinator flow.
- [x] Resolve all draft slots before serialization; use existing `FilterExpr`
  encoding and schema. Outer Save commits once; browsing/editing/cancelling
  conditions must not dispatch edit-view mutations or publish external files.
- [x] Guard stale dialogs/collection switches so a draft opened for one working
  copy cannot be saved into another collection with overlapping IDs. Preserve
  draft text and show useful backend errors on failure instead of closing.
- [x] Keep yellow view tiles, hierarchy warning links and rule repair working
  after display flattening and structural edits; recompute committed issue paths
  from the saved AST. Successful repair clears warnings as before.
- [x] Ensure adding tasks inside saved views still uses the same creation
  defaults and complete-filter acceptance; shared completion/visibility controls
  must not be conflated with expression editing.

Live draft result previews, query-language input, AI assistance, new relative
date operators, templates, rule dragging and undo/history are separate possible
follow-ups. They are not prerequisites for this approved presentation rework.

## 7. Verify behavior and prevent regressions

- [x] Add meaningful draft/projection tests and focused widget tests; adapt
  existing tests to the new interactions rather than relying on old Rule labels.
- [x] Cover this minimum acceptance matrix:

| Scenario | Expected result |
| --- | --- |
| Start AND/OR, fill left/right slots | Correct operands; no accidental All placeholder |
| Inner versus outer plus in `A AND (B OR C)` | Only the selected chain gets the new operand |
| Extend AND/OR and add same-operator group | One readable same-operator chain; order retained |
| Add different group or combine one operand | Explicit parentheses; unchanged sibling scope |
| Change AND to OR | Existing operands and values retained |
| Nested XOR / NOT and duplicate alternatives | Original exact semantics and boundaries retained |
| Edit every leaf and all comparison/options | Correct round-trip encoding and summaries |
| Form Cancel, view Cancel and unchanged/name-only Save | Expected draft isolation; unchanged filter behavior |
| Remove first/middle/last/only operand | Valid predictable draft, no unintended match-all change |
| Saved empty/single/deep groups and nested tag OR/XOR | Matching and creation hints preserved |
| Duplicate names / deleted container repair | Correct IDs; accurate warning and repair mapping |
| Long text, 2x text, narrow/short/landscape/keyboard layout | Readable conditions and reachable controls; no clipping |
| Resize/relayout while editing | Focus, text selection and draft identity retained |
| Failed save, pending external file, collection switch | No wrong-document mutation or lost draft |

- [x] Run workspace Rust tests if expression/storage/application behavior is
  touched, and regression tests for matching versus creation hints. Reuse the
  existing evaluator; do not add a second matching engine in Dart.
- [x] Run Flutter analysis and shared unit/widget tests, architecture checks,
  and the real Rust-backed Linux integration flow. Include creation, saving,
  reopening, repair and adding a task through the resulting view.
- [x] Follow repository CI/native build policy. Run native integration and APK
  builds sequentially in one checkout (integration plugin registration can
  interfere with a concurrent release build). A docs-only plan needs no builds.
- [x] If distributing a test APK, increment Android build number, retain the
  permanent signing identity and verify ELF plus ZIP 16 KB alignment. Never
  mark physical checks complete based on host tests or packaging success.

## 8. Document, review and hand off

- [x] Update implemented requirements, checklist and this plan with actual
  evidence. Add `docs/view-expression-editor-acceptance.md` with disposable-view
  steps for Pixel/GrapheneOS, Windows and Fedora.
- [ ] Physically verify scoped pluses, mixed groups, every rule type, save/cancel,
  deleted-container repair, large text/keyboard/rotation on Pixel and responsive
  mouse/keyboard usage on desktop. Record these separately if owner testing is
  still pending.
- [x] Commit/push and open a PR into `development`, showing before/after
  expressions and matching/creation compatibility evidence. Do not merge or
  create a stable release/tag without the owner's instruction.

Completion means the agreed infix interaction works for simple and complex
existing rules, saved-file and task-creation behavior are preserved, shared
verification passes, and remaining physical acceptance is clearly recorded.

## Research background (not the approved visual layout)

The earlier research compared simple filters, structured groups, filter tokens,
query text, block editors and AI-assisted creation. The owner explicitly chose
an infix expression with Option-A narrow wrapping, not logical headers wrapping
cards. Do not substitute the earlier ALL/ANY-heading mockup for this design.

- [Airtable condition/group mechanics](https://support.airtable.com/articles/9290731839-filtering-records-using-conditions)
- [Notion simple and advanced filters](https://www.notion.com/help/views-filters-and-sorts)
- [Carbon filter interaction patterns](https://www.carbondesignsystem.com/building-blocks/core/patterns/filtering)
- [Progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/)
- [Todoist query syntax](https://www.todoist.com/help/todoist/features/introduction-to-filters-V98wIH)

## Implementation and verification evidence

- Shared editor implemented on `codex/view-expression-editor-plan`, PR #17 into
  development. Android, Windows and Linux use the same widgets and draft helper.
- Existing Rust `FilterExpr`, matching, creation hints and schema remain unchanged.
  Same-op chains are visually coalesced; unchanged/name-only saves retain the
  stored structure, including nested tag alternatives and valid degenerate groups.
- 97 shared Flutter tests pass (75 existing plus 22 new draft/editor checks).
  Library/test/integration analysis is clean. All 67 Rust and 13 Python checks pass.
- Real Linux integration passes nested-tag-OR hint equality across editor save,
  accepted task creation, save/reopen and deleted-container repair through the
  new condition form. Native phone-layout integration also passes view editing/saving, keyboard
  transitions, item-editor flushing, scrolling and descendant drag/drop.
  Android release packaging is verified below.
- Host font-rendered narrow/wide captures inspected for parentheses, connector
  placement, plus scope, and action reachability; 2x text/long values are covered.
- A rapid text-edit/checkbox regression is fixed by merging field patches into
  the latest form state; date-presence updates also preserve current state and
  clear unused values. Collection/view guards execute after queue waits.
- Physical Pixel/Windows/Fedora acceptance remains unchecked. See
  [acceptance guide](view-expression-editor-acceptance.md).

- Runtime/source commit: `e28226e852cc4259764ecdfa0f67cf8f89caca37`.
- ARM64 Android release build 0.2.2 build 11 passed. Candidate:
  `/workspace/ihtd/dist/view-expression-editor/IHTD-0.2.2-build11-android-arm64-test.apk`.
  SHA-256: `5c9a5f0502863938246ab5866087e143be8cdb03d48b2328ef666962a74311ec`.
  Signature matches the pinned permanent certificate. APK ZIP alignment is 16 KB;
  ELF LOAD alignment is 64 KB for app/Flutter and 16 KB for JNI/Rust bridge.
  This is an in-place test update for existing permanent-key installations.
- Final focused editor tests also pass without the optional capture font;
  final analysis of library/test/integration sources is clean. No runtime changes
  were made after source commit `e28226e`.
